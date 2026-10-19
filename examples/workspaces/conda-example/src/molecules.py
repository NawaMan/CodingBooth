"""
Molecule Lab - shared helpers for the CLI (molecule.py) and Molecules.ipynb.

RDKit is the reason this example uses conda: it is a C++ toolkit with Python
bindings, and conda-forge ships it prebuilt for every platform the booth runs on.
"""

from rdkit import Chem
from rdkit.Chem import Crippen, Descriptors, Lipinski, rdDepictor, rdMolDescriptors

# CoordGen lays out bridged ring systems (morphine, rifampicin) more legibly
# than RDKit's default 2-D depiction.
rdDepictor.SetPreferCoordGen(True)

# A small shelf of well-known molecules, by SMILES. Lower-case names are the keys
# the CLI accepts (`molecule.py caffeine`).
DRUGS = {
    "aspirin":      "CC(=O)OC1=CC=CC=C1C(=O)O",
    "caffeine":     "CN1C=NC2=C1C(=O)N(C(=O)N2C)C",
    "ibuprofen":    "CC(C)CC1=CC=C(C=C1)C(C)C(=O)O",
    "paracetamol":  "CC(=O)NC1=CC=C(C=C1)O",
    "nicotine":     "CN1CCCC1C2=CN=CC=C2",
    "dopamine":     "C1=CC(=C(C=C1CCN)O)O",
    "serotonin":    "C1=CC2=C(C=C1O)C(=CN2)CCN",
    "metformin":    "CN(C)C(=N)N=C(N)N",
    "morphine":     "CN1CCC23C4C1CC5=C2C(=C(C=C5)O)OC3C(C=C4)O",
    "penicillin-g": "CC1(C(N2C(S1)C(C2=O)NC(=O)CC3=CC=CC=C3)C(=O)O)C",
    "atorvastatin": "CC(C)C1=C(C(=C(N1CCC(CC(CC(=O)O)O)O)C2=CC=C(C=C2)F)C3=CC=CC=C3)C(=O)NC4=CC=CC=C4",
    "rifampicin":   "CC1C=CC=C(C(=O)NC2=C(C(=C3C(=C2O)C(=C(C4=C3C(=O)C(O4)(OC=CC(C(C(C(C(C(C1O)C)O)C)OC(=O)C)C)OC)C)C)O)O)C=NN5CCN(CC5)C)C",
}


def to_mol(name_or_smiles: str) -> tuple[str, Chem.Mol]:
    """Resolve a shelf name or a raw SMILES string to (label, molecule)."""
    key = name_or_smiles.lower()
    smiles = DRUGS.get(key, name_or_smiles)
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        raise ValueError(f"not a known name or a valid SMILES: {name_or_smiles}")
    label = key if key in DRUGS else smiles
    return label, mol


def properties(mol: Chem.Mol) -> dict:
    """Drug-likeness descriptors, plus Lipinski's rule of five.

    The rule says an oral drug usually has MW <= 500, logP <= 5, at most 5
    H-bond donors and at most 10 acceptors; one violation is tolerated.
    """
    props = {
        "formula":    rdMolDescriptors.CalcMolFormula(mol),
        "mol_weight": Descriptors.MolWt(mol),
        "logp":       Crippen.MolLogP(mol),
        "h_donors":   Lipinski.NumHDonors(mol),
        "h_acceptors": Lipinski.NumHAcceptors(mol),
        "tpsa":       rdMolDescriptors.CalcTPSA(mol),
        "rot_bonds":  Lipinski.NumRotatableBonds(mol),
        "rings":      rdMolDescriptors.CalcNumRings(mol),
    }
    violations = sum([
        props["mol_weight"]  > 500,
        props["logp"]        > 5,
        props["h_donors"]    > 5,
        props["h_acceptors"] > 10,
    ])
    props["lipinski_violations"] = violations
    props["lipinski_pass"] = violations <= 1
    return props
