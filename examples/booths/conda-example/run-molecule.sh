#!/bin/bash
# Molecule Lab: drug-likeness of a molecule, by name or SMILES
cd "$(dirname "$0")"
python src/molecule.py "$@"
