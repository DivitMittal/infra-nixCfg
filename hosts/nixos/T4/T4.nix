# T4 — the medium-spec t640: home-lab services. Add each service as its own
# file in this directory (import-tree picks it up), as a native NixOS module
# where one exists. AI work goes to T3's Ollama (http://T3:11434) rather than
# running here, so services don't compete with inference for RAM.
#
# Planned here as well: the heavier observability pieces (Loki/Tempo from
# PR #36) once MON1's light stack is running.
_: {}
