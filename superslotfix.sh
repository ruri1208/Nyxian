#!/bin/bash
set -e

DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

BUNDLES=(
    "Runestone_Runestone.bundle"
    "SwiftTerm_SwiftTerm.bundle"
    "TreeSitterC_TreeSitterC.bundle"
    "TreeSitterObjc_TreeSitterObjc.bundle"
    "TreeSitterSwift_TreeSitterSwift.bundle"
    "TreeSitterCPP_TreeSitterCPP.bundle"
    "TreeSitterXML_TreeSitterXML.bundle"
    "TreeSitterXML_TreeSitterDTD.bundle"
)

for bundle in "${BUNDLES[@]}"; do
    SRC="${BUILT_PRODUCTS_DIR}/${bundle}"
    
    if [ -d "$SRC" ]; then
        echo "embedding $bundle"
        rm -rf "${DEST}/${bundle}"
        ditto "$SRC" "${DEST}/${bundle}"
    else
        echo "warning: $bundle not found at $SRC"
    fi
done
