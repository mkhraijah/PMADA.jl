push!(LOAD_PATH,"../src/")
using Documenter, PMADA

makedocs(
    modules = [PMADA],
    sitename = "PMADA.jl",
    authors = "Mohannad Alkhraijah",
    format = Documenter.HTML(
        analytics = "",
        mathengine = Documenter.MathJax(),
        collapselevel=1,
    ),
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "Quick Start Guide" => "quickguide.md",
            "Data Structure" => "data_structure.md",
            "Problem Specification and Algorithm Selection" => "specification.md" , 
            "Distributed Algorithms" => [
                "ADMM" => "admm.md",
                "ATC" => "atc.md",
                "APP" => "app.md",
                "ALADEN" => "aladin.md"
            ],
            "Utilities" => "utilities.md"
        ],
        "Tutorials" => [
            "Using PMADA" => "tutorial.md",
        "User-defined Algorithm" => "newalgorithm.md"
        ],
        "Library" => "library.md"
    ]
)

deploydocs(
    repo = "github.com/mkhraijah/PMADA.jl"
)
