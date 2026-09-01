"""GENERATED. Do not hand-edit -- run `build.py -- vocab`.

The closed vocabulary of asset families. A new VARIANT of an existing family
costs nothing; a new FAMILY costs a regeneration, which is the friction that
stops the vocabulary drifting into forty near-synonyms.

While FAMILIES is empty the vocabulary is OPEN: registry accepts anything and
prints a warning every run, and verify.assert_names FAILS the sweep. That
combination is deliberate. An open vocabulary is a legitimate bootstrap state
and an illegitimate permanent one, and in the parent project the equivalent
fallback quietly disabled a check for weeks because nothing made noise about
it.
"""

FAMILIES = frozenset({
    'bridge',
    'bush',
    'crop',
    'fence',
    'flower',
    'folk',
    'fruit',
    'grass',
    'ground',
    'house',
    'rock',
    'shrine',
    'stall',
    'tree',
    'well',
})

# Floor for the selftest ratchet: the number of negative controls that must
# exist. It may grow, never shrink -- a case cannot silently disappear.
SELFTEST_MIN = 0
