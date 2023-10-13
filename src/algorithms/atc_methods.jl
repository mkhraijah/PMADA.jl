###############################################################################
#                     Build methods for ATC algorithm                        #
###############################################################################

"""
ATC algorithm module contains build and update methods
"""
module atc_methods
using ..PowerModelsADA

"solve distributed OPF using ATC algorithm"
function solve_method(data, model_type::DataType, optimizer; kwargs...)
    solve_dopf(data, model_type, optimizer, atc_methods; kwargs...)
end

"initialize the ATC algorithm"
function initialize_method(data::Dict{String, <:Any}, model_type::DataType; kwargs...)

    area_id = get_area_id(data)
    areas_id = get_areas_id(data)
    deleteat!(areas_id, areas_id .== area_id) # remove the same area from the list of areas_id
    initialization_method = get(kwargs, :initialization_method, "flat")

    # primal and dual shared variables
    data["shared_variable"] = initialize_shared_variable(data, model_type, area_id, areas_id, "shared_variable", initialization_method)

    data["received_variable"] = initialize_shared_variable(data, model_type, area_id, areas_id, "received_variable", initialization_method)

    data["dual_variable"] = initialize_shared_variable(data, model_type, area_id, areas_id, "dual_variable", initialization_method)

    # distributed algorithm settings
    initialize_dopf!(data, model_type; kwargs...)

    # initialize ATC parameters
    data["parameter"] = Dict( 
        "alpha" => Float64(get(kwargs, :alpha, 1.05)),
        "beta" => Float64(get(kwargs, :beta, 1)),
        "beta_max" => Float64(get(kwargs, :beta_max, 1e6)))

end

"build PowerModel object for the ATC algorithm"
function build_method(pm::AbstractPowerModel)

    # define variables
    variable_opf(pm)

    # define constraints
    constraint_opf(pm)
  
    # define objective function
    objective_min_fuel_and_consensus!(pm, objective_atc)
end

"ATC algorithm objective function"
function objective_atc(pm::AbstractPowerModel)

    ## ATC parameters
    beta = pm.data["parameter"]["beta"]

    ## data
    shared_variable_local = pm.data["shared_variable"]
    shared_variable_received = pm.data["received_variable"]
    dual_variable = pm.data["dual_variable"]

    ## objective function
    objective = 0
    for area in keys(dual_variable)
        for variable in keys(dual_variable[area])
            for idx in keys(dual_variable[area][variable])
                v = PowerModelsADA._var(pm, variable, idx)
                v_central = (shared_variable_local[area][variable][idx] + shared_variable_received[area][variable][idx])/2
                v_dual = dual_variable[area][variable][idx]

                objective += (beta * (v - v_central))^2 + v_dual * (v - v_central)
            end
        end
    end

    return objective
end

"update the ATC algorithm data after each iteration"
function update_method(data::Dict{String, <:Any})
    
    ## ATC parameters
    alpha = data["parameter"]["alpha"]
    beta  = data["parameter"]["beta"]
    beta_max = data["parameter"]["beta_max"]

    ## data
    shared_variable_local = data["shared_variable"]
    shared_variable_received = data["received_variable"]
    dual_variable = data["dual_variable"]

    ## update dual variable
    ## update dual variable
    for area in keys(dual_variable)
        for variable in keys(dual_variable[area])
            for idx in keys(dual_variable[area][variable])
                v_primal = shared_variable_local[area][variable][idx]
                v_central = (shared_variable_local[area][variable][idx] + shared_variable_received[area][variable][idx])/2
                v_dual = dual_variable[area][variable][idx]

                data["dual_variable"][area][variable][idx] = v_dual  + 2 * beta^2 * (v_primal - v_central)
            end
        end
    end

    ## update ATC parameter
    if beta < beta_max
        data["parameter"]["beta"] *= alpha
    end

    calc_mismatch!(data, central=true)
    update_flag_convergence!(data)
    save_solution!(data)
    update_iteration!(data)
end

post_processors = [update_solution!, update_shared_variable!]

push!(_pmada_global_keys, "shared_variable", "received_variable", "dual_variable")

end

"""
    solve_dopf_atc(data::Dict{String, <:Any}, model_type::DataType, optimizer; 
    mismatch_method::String="norm", tol::Float64=1e-4, max_iteration::Int64=1000, 
    print_level = true, print_optimizer_info::Bool=false, alpha::Real=1000, beta::Real = 1)

Solve the distributed OPF problem using ATC algorithm.
# Arguments:
- data::Dict{String, <:Any} : dictionary contains case in PowerModel format
- model_type::DataType : power flow formulation (PowerModel type)
- optimizer : optimizer JuMP initiation object
- mismatch_method::String="norm" : mismatch calculation method (norm, max)
- tol::Float64=1e-4 : mismatch tolerance
- max_iteration::Int64=1000 : maximum number of iteration
- print_level::Int64=1 : print mismatch after each iteration and result summary 
- alpha::Real=1.05 : algorithm parameter
- beta::Real=1.0 : algorithm parameter
"""
solve_dopf_atc = atc_methods.solve_method

# export the algorithm methods module and solve method
export atc_methods, solve_dopf_atc