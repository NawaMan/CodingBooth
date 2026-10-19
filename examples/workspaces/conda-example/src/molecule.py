#!/usr/bin/env python3
"""
Molecule Lab - drug-likeness of a molecule, from its name or its SMILES

Demonstrates RDKit (installed via conda) from the command line. The notebook,
Molecules.ipynb, draws the same molecules and charts them.
"""

import sys

from molecules import DRUGS, properties, to_mol


def format_props(label: str, props: dict) -> str:
    verdict = "pass" if props["lipinski_pass"] else "FAIL"
    lines = [
        f"{label}",
        f"  Formula:        {props['formula']}",
        f"  Mol. weight:    {props['mol_weight']:.2f} g/mol",
        f"  logP:           {props['logp']:.2f}",
        f"  H-bond donors:  {props['h_donors']}",
        f"  H-bond accept.: {props['h_acceptors']}",
        f"  TPSA:           {props['tpsa']:.1f} Å²",
        f"  Rotatable:      {props['rot_bonds']}",
        f"  Rings:          {props['rings']}",
        f"  Lipinski:       {verdict} ({props['lipinski_violations']} violation(s))",
    ]
    return "\n".join(lines)


def show_help():
    print("Molecule Lab (using RDKit)")
    print("")
    print("Drug-likeness descriptors and Lipinski's rule of five for a molecule.")
    print("")
    print("Usage: molecule.py <name|SMILES> [name|SMILES...]")
    print("       molecule.py --list")
    print("")
    print("Examples:")
    print("  molecule.py caffeine")
    print("  molecule.py aspirin ibuprofen")
    print("  molecule.py 'C1=CC=CC=C1'        # benzene, by SMILES")
    print("")
    print("Known names: " + ", ".join(DRUGS))


def main():
    args = sys.argv[1:]

    if not args or args[0] in ("-h", "--help"):
        show_help()
        return

    if args[0] == "--list":
        for name, smiles in DRUGS.items():
            print(f"{name:<14} {smiles}")
        return

    failed = False
    for i, arg in enumerate(args):
        try:
            label, mol = to_mol(arg)
        except ValueError as error:
            print(f"Error: {error}", file=sys.stderr)
            failed = True
            continue
        if i:
            print("")
        print(format_props(label, properties(mol)))

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
