"""
    SiteState

Logical Stage-0 parameter-site state:

    (q, allocated, superplastic, hot_handle)

`q` is always one of -1, 0, +1. A superplastic site must own a nonzero
hot-pool handle; a non-superplastic site must not own one. Cross-checking that
a nonzero handle is actually allocated in a particular `HotPool` is performed
by `check_invariants(substrate)`.
"""
mutable struct SiteState
    q::Int8
    allocated::Bool
    superplastic::Bool
    hot_handle::Int32

    function SiteState(q::Integer, allocated::Bool=false,
                       superplastic::Bool=false, hot_handle::Integer=0)
        q in (-1, 0, 1) || error("HardFailure: site q must be in {-1,0,+1}, got $q")
        hot_handle >= 0 || error("HardFailure: hot_handle must be >= 0, got $hot_handle")
        !allocated && superplastic && error("HardFailure: vacant site cannot be superplastic")
        superplastic && hot_handle == 0 && error("HardFailure: superplastic site lacks hot handle")
        !superplastic && hot_handle != 0 && error("HardFailure: non-superplastic site owns hot handle $hot_handle")
        new(Int8(q), allocated, superplastic, Int32(hot_handle))
    end
end

SiteState(; q::Integer=0, allocated::Bool=false,
          superplastic::Bool=false, hot_handle::Integer=0) =
    SiteState(q, allocated, superplastic, hot_handle)

is_valid_q(site::SiteState)::Bool = site.q in (-1, 0, 1)
has_valid_hot_handle(site::SiteState)::Bool = site.hot_handle != 0

function check_invariants(site::SiteState)
    is_valid_q(site) || error("HardFailure: site q must be in {-1,0,+1}, got $(site.q)")
    !site.allocated && site.superplastic && error("HardFailure: vacant site cannot be superplastic")
    site.superplastic && site.hot_handle == 0 && error("HardFailure: superplastic site lacks hot handle")
    !site.superplastic && site.hot_handle != 0 && error("HardFailure: non-superplastic site owns hot handle $(site.hot_handle)")
    return true
end
