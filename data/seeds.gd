class_name Seeds

## Default seeds for the game's random systems.
##
## Map generation used to call unseeded random at module load, so blocked
## tiles landed differently on every page load. Blocked tiles remove build
## space, so that was gameplay randomness that could not be reproduced.

const DEFAULT_DEMO_MAP_SEED := 20260804
const DEFAULT_MAP2_SEED := 20260805
const DEFAULT_MAP3_SEED := 20260806
const DEFAULT_DECORATION_SEED := 771144

## Which of the six ground cards each tile gets. Separate from the decoration
## seed so ground variety does not move when decoration does.
const DEFAULT_GROUND_SEED := 20260821
