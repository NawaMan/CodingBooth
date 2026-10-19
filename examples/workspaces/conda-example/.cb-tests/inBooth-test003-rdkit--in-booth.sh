#!/bin/bash
# RDKit came from conda-forge into the conda env, and it can parse a molecule.
set -euo pipefail
echo "=== Testing RDKit (conda) ==="
python -c "
from rdkit import Chem, rdBase
from rdkit.Chem import rdMolDescriptors
mol = Chem.MolFromSmiles('c1ccccc1')
print('RDKit version:', rdBase.rdkitVersion)
assert rdMolDescriptors.CalcMolFormula(mol) == 'C6H6'
"
conda list -p "$(python -c 'import sys; print(sys.prefix)')" '^rdkit$' | grep -q conda-forge
