# [Error Analysis](@id jetanalysis)

Julia's type system is quite expressive and its type inference is strong enough to generate
fairly optimized code from a highly generic program written in a concise syntax.
But as opposed to other statically-compiled languages, Julia by design does _not_ error nor
warn anything even if it detects possible errors during its compilation process no matter
how serious they are. In essence, Julia achieves highly generic and composable programming
by delaying all the errors and warnings to the runtime.

This is a core design choice of the language. On the one hand, Julia's dynamism
allows it to work in places where data types can not be fully decided ahead of runtime
(e.g. when the program is duck-typed with generic pieces of code, or when the program
consumes some data that is only known at runtime). On the other hand, with Julia, it's
not straightforward to have such modern development experiences that a static language can
typically offer, as like static type checking and rich IDE features.

JET is a trial to get the best of both worlds: can we have a sufficiently useful static
checking without losing all the beauty of Julia's dynamism and composability?
JET's approach is very different from
["gradual typing"](https://en.wikipedia.org/wiki/Gradual_typing),
that is a common technique to bring static analysis into a dynamic language, as used for
e.g. [mypy](https://github.com/python/mypy) for Python and
[TypeScript](https://www.typescriptlang.org/) for JavaScript.
Rather, JET's static analysis is powered by Julia's builtin type inference system, that
based on a technique called
["abstract interpretation"](https://en.wikipedia.org/wiki/Abstract_interpretation).
This way JET can also analyze _just a normal_ Julia program and smartly detect possible
errors statically, without requiring any additional setups like scattering type annotations
just for the sake of analysis but preserving original polymorphism and composability of
the program, as effectively as the Julia compiler can optimize your Julia program.

## [Quick Start](@id jetanalysis-quick-start)

First, you need to install JET: JET is an ordinary Julia package, so you can install it via
Julia's built-in package manager and use it as like other packages.
```@repl quickstart
; # ] add JET # install JET via the built-in package manager

using JET
```

Let's start with the simplest example: how JET can find anything wrong with `sum("julia")`?
[`@report_call`](@ref) and [`report_call`](@ref) analyzes a given function call and report
back possible problems. They can be used in a similar way as
[`@code_typed`](https://docs.julialang.org/en/v1/stdlib/InteractiveUtils/#InteractiveUtils.@code_typed)
and [`code_typed`](https://docs.julialang.org/en/v1/base/base/#Base.code_typed).
Those [interactive entry points](@ref jetanalysis-interactive-entry) are the easiest
way to use JET:
```@repl quickstart
@report_call sum("julia")
```

So JET found two possible problems. Now let's see how they can occur in _actual execution_:
```@repl quickstart
sum("julia") # will lead to `MethodError: +(::Char, ::Char)`
sum("") # will lead to `MethodError: zero(Type{Char})`
```

We should note that `@report_call sum("julia")` could detect both of those two different
errors that can happen at runtime. This is because `@report_call` does a static analysis —
it analyzes the function call in a way that does not rely on one instance of runtime
execution, but rather it reasons about all the possible executions!
This is one of the biggest advantages of static analysis because other alternatives to
check software qualities like "testing" usually rely on _some_ runtime execution and they
can only cover a subset of all the possible executions.

As mentioned above, JET is designed to work with _just a normal_ Julia program.
Let's define new arbitrary functions and run JET on it:
```@repl quickstart
function foo(s0)
    a = []
    for s in split(s0)
        push!(a, bar(s))
    end
    return sum(a)
end

bar(s::String) = parse(Int, s)

@report_call foo("1 2 3")
```

Now let's fix this problematic code.
First, we can fix the definition of `bar` so that it accepts generic `AbstractString` input.
JET's analysis result can be dynamically updated when we refine a function definition,
and so we just need to add a new `bar(::AbstractString)` definition.
As for the second error, let's assume, for some reason, we're not interested in fixing it and
we want to ignore errors that may happen within `Base`. Then we can use the
[`target_modules`](@ref result-config) configuration to limit the analysis scope to
the current module context to ignore the possible error that may happen within `sum(a)`[^1].

[^1]: We used `target_modules` just for the sake of demonstration. To make it more
      idiomatic, we should initialize `a` as typed vector `a = Int[]`, and then we won't
      get any problem from `sum(a)` even without the `target_modules` configuration.

```@repl quickstart
# hot fix the definition of `bar`
bar(s::AbstractString) = parse(Int, s)

# now no errors should be reported !
@report_call target_modules=(@__MODULE__,) foo("1 2 3")
```

So far, we have used the default error analysis pass, which collects problems according to
one specific (somewhat opinionated) definition of "errors" (see the [`JET.BasicPass`](@ref) for more details).
JET offers other error reporting passes, including the "sound" error detection ([`JET.SoundPass`](@ref))
as well as the simpler "typo" detection pass ([`JET.TypoPass`](@ref))[^2].
They can be switched using the `mode` configuration:

[^2]: JET offers the framework to define your own abstract interpretation-based analysis.
      See [`AbstractAnalyzer`-Framework](@ref) if interested.

```@repl quickstart
function myifelse(cond, a, b)
    if cond
        return a
    else
        return b
    end
end

# the default analysis pass doesn't report "non-boolean (T) used in boolean context" error
# as far as there is a possibility when the condition "can" be bool (NOTE: Bool <: Integer)
report_call(myifelse, (Integer, Int, Int))

# the sound analyzer doesn't permit such a case: it requires the type of a conditional value to be `Bool` strictly
report_call(myifelse, (Integer, Int, Int); mode=:sound)

function strange_sum(a)
    if rand(Bool)
        undefsum(a)
    else
        sum(a)
    end
end

# the default analysis pass will report both problems:
# - `undefsum` is not defined
# - `sum(a::Vector{Any})` can throw when `a` is empty
@report_call strange_sum([])

# the typo detection pass will only report the "typo"
@report_call mode=:typo strange_sum([])
```

We can use [`@test_call`](@ref) and [`test_call`](@ref) to assert that your program is free
from problems that `@report_call` can detect.
They work nicely with [`Test` standard library](https://docs.julialang.org/en/v1/stdlib/Test/)'s
unit-testing infrastructure:
```@repl quickstart
@test_call target_modules=(@__MODULE__,) foo("1 2 3")

using Test

# we can get the nice summery using `@testset` !
@testset "JET testset" begin
    @test_call target_modules=(@__MODULE__,) foo("1 2 3") # should pass

    test_call(myifelse, (Integer, Int, Int); mode=:sound)

    @test_call broken=true foo("1 2 3") # `broken` and `skip` options are supported

    @test foo("1 2 3") == 6 # of course other `Test` macros can be used in the same place
end
```

JET uses JET itself in its test pipeline: JET's static analysis has been proven to
be very useful and helped its development a lot.
If interested, take a peek at [JET's `"self check !!!"` testset](https://github.com/aviatesk/JET.jl/blob/master/test/runtests.jl).

Lastly, let's see the example that demonstrates JET can analyze a "top-level" program.
The top-level analysis should be considered as a somewhat experimental feature, and at this moment
you may need additional configurations to run it correctly. Please read the descriptions of
[top-level entry points](@ref jetanalysis-toplevel-entry) and choose an appropriate entry point for
your use case. Here we run [`report_file`](@ref) on [demo.jl](https://github.com/aviatesk/JET.jl/blob/master/demo.jl).
It automatically extracts and loads "definitions" of functions, structs and such,
and then analyzes their "usages" statically:
```@repl quickstart
report_file(normpath(Base.pkgdir(JET), "demo.jl"))
```


## [Entry Points](@id jetanalysis-entry)

### [Interactive Entry Points](@id jetanalysis-interactive-entry)

JET offers interactive analysis entry points that can be used similarly to
[`code_typed`](https://docs.julialang.org/en/v1/base/base/#Base.code_typed) and its family:
```@docs
JET.@report_call
JET.report_call
```

### [`Test` Integration](@id jetanalysis-test-integration)

JET also exports entries that are fully integrated with [`Test` standard library](https://docs.julialang.org/en/v1/stdlib/Test/)'s unit-testing infrastructure.
It can be used in your test suite to assert your program is free from errors that JET can detect:
```@docs
JET.@test_call
JET.test_call
```

### [Top-level Entry Points](@id jetanalysis-toplevel-entry)

JET can also analyze your "top-level" program: it can just take your Julia script or package
and will report possible errors.

Note that JET will analyze your top-level program "half-statically": JET will selectively
interpret and load "definitions" (like a function or struct definition) and try to
simulate Julia's top-level code execution process.
While it tries to avoid executing any other parts of code like function calls and analyzes
them based on abstract interpretation instead (and this is a part where JET statically analyzes your code).
If you're interested in how JET selects "top-level definitions", please see [`JET.virtual_process`](@ref).

!!! warning
    Because JET will interpret "definitions" in your code, that part of top-level analysis
    certainly _runs_ your code. So we should note that JET can cause some side effects from your code;
    for example, JET will try to expand all the macros used in your code, and so the side effects
    involved with macro expansions will also happen in JET's analysis process.

```@docs
JET.report_file
JET.report_and_watch_file
JET.report_package
JET.report_text
```


## [Configurations](@id jetanalysis-config)

In addition to [general configurations](@ref JET-configurations), the error analysis can take the
following specific configurations:
```@docs
JET.JETAnalyzer
JET.BasicPass
JET.SoundPass
JET.TypoPass
```
