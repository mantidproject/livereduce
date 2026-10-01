# shellcheck shell=bash
# Stand-in for SNS's nsd-app-wrap.sh. Like the real pixi_launch, it runs the command as a child
# rather than exec'ing it, so livereduce.sh stays in the tree as the service's main process.
pixi_launch() {
    shift # pixi environment name, unused here
    "$@"
}
