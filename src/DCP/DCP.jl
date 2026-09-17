"""
    DCP (Decision-making Control Process)

Abstract base type for DCP controllers.

All DCPs must implement:
    decide(dcp, snapshot) -> Action

The DCP sees only immutable declared snapshot fields.
Lifecycle application is separate via apply_action!
"""
abstract type DCP end

# Include concrete implementations
include("Snapshot.jl")
include("Actions.jl")
include("FixedRuleController.jl")

# Export the abstract type and core functions
export DCP, decide, apply_action!

"""
    decide(dcp::DCP, snapshot::Snapshot) -> Action

Generic decide function - dispatches to concrete implementations.
"""
function decide end

"""
    apply_action!(substrate, action::Action)

Applies a DCP action to the substrate.
This is where lifecycle transitions occur.
"""
function apply_action! end
