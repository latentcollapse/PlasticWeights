"""
    C6_FixedSchedule

Fixed schedule control for Stage-0.

Implements predetermined schedules for hyperparameters or transitions.
"""
struct C6_FixedSchedule <: Control
    schedule::Vector{Float32}
    current_step::Int32
    
    function C6_FixedSchedule(schedule::Vector{<:Real})
        if isempty(schedule)
            error("HardFailure: FixedSchedule cannot have empty schedule")
        end
        new(Float32.(schedule), Int32(0))
    end
end

# Placeholder implementation
const C6_FIXED_DEFAULT = C6_FixedSchedule([1.0f0])
