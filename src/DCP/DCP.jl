"""Abstract fixed-rule developmental controller interface."""
abstract type DCP end

function decide end
function apply_action! end
