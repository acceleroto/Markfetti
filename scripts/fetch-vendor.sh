#!/bin/bash
# Downloads the pinned JavaScript/CSS libraries the renderer uses into Resources/web/vendor.
# Run once (or after bumping a version). The app itself never downloads anything.
set -euo pipefail
cd "$(dirname "$0")/.."
V=Resources/web/vendor
CDN=https://cdn.jsdelivr.net/npm

get() { # get <npm path> <dest relative to vendor>
  mkdir -p "$(dirname "$V/$2")"
  curl -fsSL --retry 2 "$CDN/$1" -o "$V/$2"
  echo "  $2"
}
try() { get "$@" || echo "  (skipped $2)"; }

rm -rf "$V"; mkdir -p "$V"
echo "Fetching libraries into $V"

get markdown-it@14.1.0/dist/markdown-it.min.js                     markdown-it/markdown-it.min.js
get markdown-it-footnote@4.0.0/dist/markdown-it-footnote.min.js    markdown-it/markdown-it-footnote.min.js
get markdown-it-task-lists@2.1.1/dist/markdown-it-task-lists.min.js markdown-it/markdown-it-task-lists.min.js
get markdown-it-emoji@3.0.0/dist/markdown-it-emoji.min.js          markdown-it/markdown-it-emoji.min.js
get dompurify@3.2.4/dist/purify.min.js                             purify.min.js
get github-markdown-css@5.8.1/github-markdown.css                  github-markdown.css

# KaTeX (math)
get katex@0.16.11/dist/katex.min.js  katex/katex.min.js
get katex@0.16.11/dist/katex.min.css katex/katex.min.css
for f in $(grep -oE 'fonts/[A-Za-z0-9_-]+\.(woff2|woff|ttf)' "$V/katex/katex.min.css" | sort -u); do
  get "katex@0.16.11/dist/$f" "katex/$f"
done

# highlight.js (syntax highlighting): common bundle + extra languages GitHub also highlights
HL=@highlightjs/cdn-assets@11.10.0
get $HL/highlight.min.js              highlight/highlight.min.js
get $HL/styles/github.min.css         highlight/github.min.css
get $HL/styles/github-dark.min.css    highlight/github-dark.min.css
for lang in dockerfile powershell haskell scala elixir erlang clojure dart julia latex matlab \
            nginx protobuf cmake fortran ocaml fsharp groovy gradle vim x86asm armasm llvm \
            verilog vhdl apache properties lisp scheme prolog nim crystal d elm tcl awk \
            coffeescript handlebars http dos applescript delphi basic smalltalk ada \
            autohotkey; do
  try $HL/languages/$lang.min.js highlight/languages/$lang.min.js
done
cat "$V"/highlight/languages/*.min.js > "$V/highlight/languages.js"
rm -rf "$V/highlight/languages"

# Mermaid diagrams
get mermaid@11.4.1/dist/mermaid.min.js mermaid/mermaid.min.js

# GeoJSON / TopoJSON maps
get leaflet@1.9.4/dist/leaflet.js  leaflet/leaflet.js
get leaflet@1.9.4/dist/leaflet.css leaflet/leaflet.css
for img in layers.png layers-2x.png marker-icon.png marker-icon-2x.png marker-shadow.png; do
  get leaflet@1.9.4/dist/images/$img leaflet/images/$img
done
get topojson-client@3.1.0/dist/topojson-client.min.js leaflet/topojson-client.min.js

# STL 3D models
get three@0.160.0/build/three.module.js                   three/three.module.js
get three@0.160.0/examples/jsm/loaders/STLLoader.js       three/addons/loaders/STLLoader.js
get three@0.160.0/examples/jsm/controls/OrbitControls.js  three/addons/controls/OrbitControls.js

echo "Done: $(du -sh "$V" | cut -f1)"
