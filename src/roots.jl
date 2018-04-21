
import IntervalArithmetic: diam, isinterior

export branch_and_prune, Bisection, Newton

diam(x::Root) = diam(x.interval)

Base.size(x::Interval) = (1,)

isinterior{N}(X::IntervalBox{N}, Y::IntervalBox{N}) = all(isinterior.(X, Y))



"""
    branch_and_prune(X, contract, tol=1e-3)

Generic branch and prune routine for finding isolated roots using the `contract`
function as the contractor.

Inputs:
- `X`: `Interval` or `IntervalBox`
- `contractor`: function that determines the status of a given box `X`. It
    returns the new box and a symbol indicating the status. Current possible
    values are of type `Bisection` or `Newton`

"""
function branch_and_prune(X, contractor, tol=1e-3)
    working = [X]
    outputs = Root{typeof(X)}[]

    sizehint!(outputs, 100)
    sizehint!(working, 1000)

    while !isempty(working)
        # @show working
        X = pop!(working)

        status, output = contractor(X, tol)

        if status == :empty
            continue

        elseif status == :unique
            push!(outputs, Root(output, :unique))

        elseif diam(output) < tol
            push!(outputs, Root(output, :unknown))

        else  # branch
            X1, X2 = bisect(X)

            push!(working, X1, X2)
        end
    end

    return outputs
end


export recursively_branch_and_prune

function recursively_branch_and_prune(h, X, contractor=BisectionContractor, final_tol=1e-14)
    tol = 2
    roots = branch_and_prune(h, X, IntervalRootFinding.BisectionContractor, tol)

    while tol > 1e-14
       tol /= 2
       roots = branch_and_prune(h, roots, IntervalRootFinding.BisectionContractor, tol)
    end

    return roots
end


contains_zero(X::Interval{T}) where {T} = zero(T) ∈ X
contains_zero(X::SVector) = all(contains_zero.(X))
contains_zero(X::IntervalBox) = all(contains_zero.(X))


IntervalLike{T} = Union{Interval{T}, IntervalBox{T}}

"""
    roots(f, X, contractor, tol=1e-3)

Uses a generic branch and prune routine to find in principle all isolated roots of a function
`f:R^n → R^n` in a box `X`, or a vector of boxes.

Inputs:
- `f`: function whose roots will be found
- `X`: `Interval` or `IntervalBox`
- `contractor`: function that, when applied to the function `f`, determines
    the status of a given box `X`. It returns the new box and a symbol indicating
    the status. Current possible values are `Bisection` and `Newton`.

"""
# Contractor specific `roots` functions
function roots(f, X::IntervalLike{T}, ::Type{Bisection}, tol::Float64=1e-3) where {T}
    branch_and_prune(X, Bisection(f), tol)
end

function roots(f, X::Interval{T}, ::Type{Newton}, tol::Float64=1e-3; deriv = nothing) where {T}

    if deriv == nothing
        deriv = x -> ForwardDiff.derivative(f, x)
    end

    branch_and_prune(X, Newton(f, deriv), tol)
end

function roots(f, X::IntervalBox{T}, ::Type{Newton}, tol::Float64=1e-3; deriv = nothing) where {T}

    if deriv == nothing
        deriv = x -> ForwardDiff.jacobian(f, x)
    end

    branch_and_prune(X, Newton(f, deriv), tol)
end


roots(f, r::Root, contractor::Type{C}, tol::Float64=1e-3; deriv= nothing) where {C<:Contractor}  = roots(f, r.interval, contractor, tol; deriv = deriv)

# Acting on a Vector:

# TODO: Use previous status information about roots:
roots(f, V::Vector{Root{T}}, contractor::Type{C}, tol::Float64=1e-3; deriv = nothing) where {T, C<:Contractor} = vcat(roots.(f, V, contractor, tol; deriv = deriv)...)



# Complex:

function roots(f, Xc::Complex{Interval{T}}, contractor::Type{C}, tol::Float64=1e-3) where {T, C<:Contractor}
    g = realify(f)
    Y = IntervalBox(reim(Xc))
    rts = roots(g, Y, contractor, tol)

    return [Root(Complex(root.interval...), root.status) for root in rts]
end

function roots(f, Xc::Complex{Interval{T}}, ::Type{Newton}, tol::Float64=1e-15;
        deriv = nothing) where {T}

    g = realify(f)

    if deriv == nothing
        g_prime = x -> ForwardDiff.jacobian(g, x)
    else
        g_prime = realify_derivative(deriv)
    end

    Y = IntervalBox(reim(Xc))
    rts = roots(g, Y, Newton, tol; deriv=g_prime)

    return [Root(Complex(root.interval...), root.status) for root in rts]
end

# Default
roots(f, X, tol::Float64=1e-15; deriv = nothing) = roots(f, X, Newton, tol; deriv = deriv)
