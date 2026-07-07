# Aether #27 — build-container walking skeleton: raw_exec batch HCL
#
# This is a TEMPLATE consumed by the aether-build-container skill.
# The skill performs string substitution on the __VAR__ sentinels at
# dispatch time, then submits via `aether dev run`. The substitution
# pattern (__VAR__) is intentional alignment with existing
# aether-plugin workflow-templates.md conventions.
#
# Substitution sentinels (skill renders these before dispatch):
#   __JOB_ID__          — unique run id (ts+nonce). Job name = build-container-<id>.
#   __CTX_PATH__        — full path to staged context tarball on shared virtiofs
#                         (e.g. /opt/aether-volumes/_build-ctx/<id>.tgz)
#   __RESULT_PATH__     — full path where the task writes result.json (same
#                         shared-volume dir; skill reads it back after alloc terminal)
#   __DOCKERFILE_PATH__ — path to Dockerfile RELATIVE to extracted context root
#   __BUILD_ARGS__      — pre-formatted "--build-arg K=V --build-arg K2=V2" string;
#                         empty if no build_args. Skill is responsible for shell-safe
#                         quoting before substitution.
#   __REGISTRY__        — target registry path WITHOUT tag (e.g. forgejo.10cg.pub/10CG/aria-runner)
#   __TAG__             — immutable tag (skill derives from source_commit_sha short prefix)
#   __SRC_REF__         — original git ref (branch/tag/sha) — passed to build for --build-arg
#                         SOURCE_GIT_REF and embedded in result.json source_git_ref
#   __SRC_SHA__         — full source_commit_sha (label org.aether.source_commit_sha +
#                         result.json source_commit_sha for drift-prevention per Aria #111)
#   __SCRIPT_PATH__     — absolute path to task-script.sh on the shared virtiofs
#                         (e.g. /opt/aether-volumes/_build-ctx/<id>.sh). Skill
#                         scp's references/task-script.sh to this location at
#                         render time and chmod +x; HCL just runs it. This
#                         avoids HCL2 heredoc ${...} interpolation collisions
#                         with bash variable references inside the script.
#
# Brainstorm decisions reflected here:
#   D2  Reuses host docker daemon — Step 2 smoke iteration discovered heavy nodes
#       don't expose raw_exec (drivers=docker,exec only; security choice). Switched
#       to docker driver running a tiny docker:cli container with the host docker
#       socket and shared-virtiofs build-ctx dir bind-mounted in (DooD pattern).
#       The container's docker CLI talks to the host daemon via the socket; actual
#       build happens on host daemon (image cache, layers, push auth all stay host).
#       Container is just the orchestration shell. ~2MB image, alpine-based, needs
#       bash installed at task startup (apk add) since docker:cli ships sh only.
#   D5  Dynamic placement: constraint = node.class heavy_workload only; resources are
#       a binpack STEERING SIGNAL, not a hard cap on the docker build itself (build
#       runs in host daemon outside container cgroup accounting). restart/reschedule
#       attempts=0 — failure surfaces to skill, not silently retried/rerouted.
#   DinD context path gotcha: `docker build` resolves context paths via the daemon,
#       not the client container. Script extracts tarball to the shared-virtiofs
#       (visible identically on host and in container via mount), so the host daemon
#       sees the extracted tree when build runs.

job "build-container-__JOB_ID__" {
  datacenters = ["dc1"]
  type        = "batch"

  # D5: candidate set = all heavy nodes. Actual placement is decided by Nomad
  # bin-packing scheduler at dispatch time (the resources block below makes the
  # scheduler exclude saturated nodes). The skill's §3a pre-flight has already
  # validated registry-auth parity across these candidates before dispatch.
  constraint {
    attribute = "${node.class}"
    operator  = "="
    value     = "heavy_workload"
  }

  group "build" {
    count = 1

    # D9: alloc_timeout deadline is 1800s (skill-side polling deadline). The
    # task itself has no separate deadline — it runs until the script exits.
    # restart{attempts=0} means: on any non-zero exit, the alloc is marked
    # failed and the skill picks up the failure via aether status polling.
    restart {
      attempts = 0
    }

    # reschedule{attempts=0}: a failed batch alloc is NOT silently moved to
    # another node. Aether owner-triggered semantics — failure must reach the
    # skill so the operator (or skill) decides whether to retry.
    reschedule {
      attempts = 0
    }

    task "build" {
      driver = "docker"

      # D5 binpack steering signal. Bounds the orchestration container's
      # resource ask (it's a tiny shell + docker CLI), NOT the actual docker
      # build which happens in the host daemon outside this container's
      # cgroup. See proposal §D2 caveat + Risk Highlights.
      resources {
        cpu    = 2000  # MHz
        memory = 3000  # MB
      }

      # All parameters reach task-script.sh via env. task-script.sh is
      # scp'd to the shared virtiofs alongside the context by the skill
      # at render time (see SKILL.md Step 5). The HCL just runs it from
      # the shared path; this avoids HCL2 heredoc interpolation collisions
      # with bash ${VAR} references inside the script body (which the
      # original inline-body design hit at smoke time).
      env {
        JOB_ID          = "__JOB_ID__"
        CTX_PATH        = "__CTX_PATH__"
        RESULT_PATH     = "__RESULT_PATH__"
        DOCKERFILE_PATH = "__DOCKERFILE_PATH__"
        BUILD_ARGS      = "__BUILD_ARGS__"
        REGISTRY        = "__REGISTRY__"
        TAG             = "__TAG__"
        SRC_REF         = "__SRC_REF__"
        SRC_SHA         = "__SRC_SHA__"
      }

      # Push auth (#225): inject the write:package token (T4) from THIS run's own
      # Nomad var. The skill writes nomad/jobs/build-container-<id> with
      # FORGEJO_BOT_USER/FORGEJO_BOT_PAT just before dispatch and deletes it after
      # the build terminates (SKILL.md Step 5/8). Default workload-identity ACL
      # lets a job read variables under nomad/jobs/<its-own-id>; rendered to
      # secrets/ (tmpfs) as env so the token is never in the job spec plaintext.
      # task-script.sh logs in with it to a THROWAWAY docker config for push —
      # the mounted host /root/.docker is T2 (read:package), pull-only.
      template {
        data        = <<EOH
{{- with nomadVar "nomad/jobs/build-container-__JOB_ID__" -}}
FORGEJO_BOT_USER={{ .FORGEJO_BOT_USER }}
FORGEJO_BOT_PAT={{ .FORGEJO_BOT_PAT }}
{{- end -}}
EOH
        destination = "secrets/push.env"
        env         = true
      }

      config {
        image = "docker:cli"

        # bash bootstrap — docker:cli ships sh only; task-script.sh uses bash
        # features (local, ${var//pat/repl}). apk add bash adds ~1s cold and
        # is cached after first build. Image and bash are pulled from Docker
        # Hub via host daemon's existing access path.
        command = "/bin/sh"
        args    = [
          "-c",
          "apk add --no-cache bash >/dev/null 2>&1 && exec /bin/bash __SCRIPT_PATH__",
        ]

        # DooD mounts:
        #   docker.sock → container's docker CLI talks to host daemon
        #   /root/.docker → host registry credentials for base-image PULL during
        #     build (T2 = 10cg-ci-bot read:package). #225: PUSH no longer uses
        #     this — it holds only read:package and 401s on 10cg/* push. The
        #     script logs in with T4 (write:package) to a throwaway config and
        #     pushes with `docker --config <throwaway>`; the host config stays
        #     read-only pull auth (never written by push).
        #   shared volume → container can read ctx + script and write
        #     result.json; host daemon ALSO sees these paths (virtiofs) so
        #     docker build's context resolution works.
        mount {
          type   = "bind"
          source = "/var/run/docker.sock"
          target = "/var/run/docker.sock"
        }
        mount {
          type   = "bind"
          source = "/root/.docker"
          target = "/root/.docker"
          # NOT readonly — buildx writes activity tracking files at
          # /root/.docker/buildx/activity/ during build. Container is
          # ephemeral so any changes are lost on alloc termination; the
          # only persistent risk is buildx state leaking between runs
          # (acceptable for skeleton; sandbox via separate docker config
          # dir is a post-skeleton iteration).
        }
        mount {
          type   = "bind"
          source = "/opt/aether-volumes/_build-ctx"
          target = "/opt/aether-volumes/_build-ctx"
        }
      }
    }
  }
}
