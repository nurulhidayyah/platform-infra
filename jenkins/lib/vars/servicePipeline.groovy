// Pipeline bersama untuk setiap service di platform. Jenkinsfile sebuah repo
// service cukup berisi satu panggilan:
//
//   servicePipeline(project: 'worklog', service: 'identity')
//
// Parameter:
//   project, service  wajib; huruf kecil, angka, dan tanda hubung
//   env               environment tujuan, bawaan 'dev'; namespace = <project>-<env>
//   healthPath        untuk image Dockerfile: path yang diuji asap sebelum push
//   port              port container untuk uji asap, bawaan 8080
//
// Cara membangun dipilih dari isi repo: pom.xml berarti Maven + Jib, Dockerfile
// berarti docker build. Semua branch diuji; hanya main yang mendorong image dan
// men-deploy. Deploy = menyalin folder deploy/ repo service ke
// platform-gitops/services/<project>-<env>/<service>/ beserta kustomization.yaml
// yang menetapkan namespace dan image. Manifest di deploy/ menulis image sebagai
// `app`; tag sebenarnya diisi di sini. ApplicationSet di Argo CD mengubah setiap
// folder itu menjadi Application.
def call(Map cfg = [:]) {
  String project = checkName(cfg, 'project')
  String service = checkName(cfg, 'service')
  String envName = cfg.env ? checkName(cfg, 'env') : 'dev'
  String healthPath = cfg.healthPath ?: ''
  String port = (cfg.port ?: 8080).toString()
  String ns = "${project}-${envName}"
  String repo = "127.0.0.1:5000/${project}/${service}"

  pipeline {
    agent any
    options {
      timestamps()
      disableConcurrentBuilds()
      buildDiscarder(logRotator(numToKeepStr: '20'))
    }
    stages {
      stage('Siapkan') {
        steps {
          script {
            env.TAG = sh(returnStdout: true, script: 'git rev-parse --short=7 HEAD').trim()
            if (fileExists('pom.xml')) {
              env.BUILD_KIND = 'maven'
            } else if (fileExists('Dockerfile')) {
              env.BUILD_KIND = 'docker'
            } else {
              error('Repo service butuh pom.xml (Maven + Jib) atau Dockerfile.')
            }
            if (fileExists('deploy/kustomization.yaml')) {
              error('deploy/ hanya berisi manifest biasa; kustomization.yaml dibuat pipeline.')
            }
            echo "${ns}/${service} ${env.TAG} (${env.BUILD_KIND}, branch ${env.BRANCH_NAME})"
          }
        }
      }
      stage('Uji dan bangun (Maven)') {
        when { environment name: 'BUILD_KIND', value: 'maven' }
        steps {
          script {
            if (env.BRANCH_NAME == 'main') {
              // Jib mendorong image langsung ke registry, tanpa Docker.
              sh "./mvnw -B verify jib:build -Djib.to.image=${repo}:${env.TAG} -Djib.allowInsecureRegistries=true"
            } else {
              sh './mvnw -B verify'
            }
          }
        }
      }
      stage('Bangun image (Dockerfile)') {
        when { environment name: 'BUILD_KIND', value: 'docker' }
        steps {
          sh "docker build -t ${repo}:${env.TAG} ."
        }
      }
      stage('Uji asap') {
        when {
          allOf {
            environment name: 'BUILD_KIND', value: 'docker'
            expression { healthPath }
          }
        }
        steps {
          sh """
            docker run -d --name uji-${service}-${env.TAG} -p 127.0.0.1::${port} ${repo}:${env.TAG}
            PORT=\$(docker port uji-${service}-${env.TAG} ${port}/tcp | head -1 | cut -d: -f2)
            for i in \$(seq 1 30); do
              curl -fsS http://127.0.0.1:\$PORT${healthPath} && exit 0
              sleep 1
            done
            docker logs uji-${service}-${env.TAG}
            exit 1
          """
        }
      }
      stage('Dorong ke registry') {
        when {
          allOf {
            branch 'main'
            environment name: 'BUILD_KIND', value: 'docker'
          }
        }
        steps {
          sh "docker push ${repo}:${env.TAG}"
        }
      }
      stage('Deploy lewat platform-gitops') {
        when { branch 'main' }
        steps {
          withEnv(["NS=${ns}", "SERVICE=${service}", "REPO=${repo}"]) {
            sshagent(credentials: ['platform-gitops-deploy-key']) {
              sh '''
                set -eu
                ls deploy/*.yaml >/dev/null 2>&1 || { echo "Folder deploy/ berisi manifest *.yaml wajib ada."; exit 1; }
                rm -rf gitops
                git clone -q git@github.com:nurulhidayyah/platform-gitops.git gitops
                dir="gitops/services/$NS/$SERVICE"
                rm -rf "$dir"
                mkdir -p "$dir"
                cp deploy/*.yaml "$dir/"
                {
                  echo "# Ditulis Jenkins dari deploy/ repo $SERVICE; jangan diubah tangan."
                  echo "apiVersion: kustomize.config.k8s.io/v1beta1"
                  echo "kind: Kustomization"
                  echo "namespace: $NS"
                  echo "resources:"
                  for f in deploy/*.yaml; do echo "  - $(basename "$f")"; done
                  echo "images:"
                  echo "  - name: app"
                  echo "    newName: $REPO"
                  echo "    newTag: \\"$TAG\\""
                } > "$dir/kustomization.yaml"
                cd gitops
                git add -A "services/$NS/$SERVICE"
                if git diff --cached --quiet; then
                  echo "platform-gitops sudah memuat $SERVICE $TAG"
                  exit 0
                fi
                git -c user.name=platform-jenkins -c user.email=jenkins@platform.invalid \
                  commit -qm "deploy($NS): $SERVICE $TAG"
                for i in 1 2 3; do
                  git pull -q --rebase origin main && git push -q origin HEAD:main && exit 0
                  sleep 3
                done
                exit 1
              '''
            }
          }
        }
      }
    }
    post {
      always {
        script {
          if (env.BUILD_KIND == 'docker' && env.TAG) {
            sh "docker rm -f uji-${service}-${env.TAG} >/dev/null 2>&1 || true"
            sh "docker image rm ${repo}:${env.TAG} >/dev/null 2>&1 || true"
          }
        }
      }
    }
  }
}

private String checkName(Map cfg, String key) {
  String value = cfg[key]?.toString()
  if (!value || !(value ==~ /[a-z0-9]([a-z0-9-]*[a-z0-9])?/)) {
    error("servicePipeline: parameter '${key}' wajib, huruf kecil, angka, dan tanda hubung (dapat: ${cfg[key]})")
  }
  return value
}
