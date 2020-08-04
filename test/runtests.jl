using TypeProfiler

# global ref
# ----------

gr1(a) = return foo(a)
@profile_call gr1(0)

function gr2(a)
    @isdefined(b) && return a
end
@profile_call gr2(0)


# boolean condition check
# -----------------------

boolcond(a) = a ? a : nothing
boolcond() = (c = rand(Any[1,2,3])) ? c #=c is Any typed=# : nothing

@profile_call boolcond(1) # report
@profile_call boolcond(true) # not report
@profile_call boolcond() # not report because it's untyped


# no method error
# ---------------

@profile_call sum("julia")
@profile_call sum(Char[])
@profile_call sum([]) # TODO: the actual error (i.e. no method for `zero(Any)` is buriled in "Too many methods matched")

# old
# ---

@profile_call sum("julia")
@profile_call sum([])

fib(n) = n <= 2 ? n : fib(n - 1) + fib(n - 2)
@profile_call fib(100) # never ends otherwise

fib′(n) = n <= 2 ? n : fib′′(n - 1) + fib′(n′ - 2)
@profile_call fib′(100) # never ends otherwise
