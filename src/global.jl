###############################################################################
#     Methods to wrap the distributed algorithm to run in a global scope      #
###############################################################################


## wrapping method to run distributed algorithms
function run_dopf(data::Dict{String, <:Any}, model_type::Type, build_method::Function, update_method::Function, optimizer; alpha::Real=1000, beta::Real=0, gamma::Real=0, initialize_method::Function=initialize_dpm!, tol::Float64=1e-4, max_iteration::Int64=1000, verbose = true)


    ## Obtain areas ids
    areas_id = get_areas_id(data)

    ## Decompose the system into several subsystem return PowerModel
    data_area = Dict{Int64, Any}()
    for i in areas_id
        data_area[i] = decompose_system(data, i)
    end

    ## Initilize distributed power model parameters
    for i in areas_id
        initialize_method(data_area[i], model_type, alpha=alpha, tol=tol, max_iteration=max_iteration)
    end

    ## Initialaize the algorithms counters
    iteration = 1
    flag_convergance = false

    ## start iteration
    while iteration < max_iteration && flag_convergance == false

        ## solve local problem and update solution
        for i in areas_id
            update_method(data_area[i])
            result = solve_model(data_area[i], model_type, optimizer, build_method)
            update_shared_primal!(data_area[i], result["solution"])
        end

        ## Share solution
        for i in areas_id # sender subsystem
            for j in areas_id # receiver subsystem
                if i != j && string(i) in keys(data_area[j]["shared_primal"])
                    shared_data = send_shared_data(i, j, data_area[i], serialize = false)
                        ### Communication ####
                    receive_shared_data!(i, shared_data, data_area[j])
                end
            end
        end

        ## Calculate mismatches and update convergance flags
        for i in areas_id
            calc_mismatch!(data_area[i],2)
            update_flag_convergance!(data_area[i], tol)
        end

        ## Check global convergance and update iteration counters
        flag_convergance = check_flag_convergance(data_area)

        if verbose
            mismatch = calc_global_mismatch(data_area)
            println("Iteration = $iteration, mismatch = $mismatch")
            if flag_convergance
                println("Consistency achived within $tol")
            end
        end

        iteration += 1

    end

    return data_area
end



function decompose_system(data::Dict{String, <:Any})
    areas_id = get_areas_id(data)
    data_area = Dict{Int64, Any}()
    for i in areas_id
        data_area[i] = decompose_system(data, i)
    end
    return data_area
end

##
function initialize_dpm!(data_area::Dict{Int64, <:Any}, optimizer, model_type)
    for i in keys(data_area)
        initialize_dpm!(data_area[i], optimizer, model_type)
    end
end

##
function update_subproblem(data_area::Dict{Int64, <:Any}, model_type, build_method::Function, alpha::Real=1000, tol::Float64=1e-4, max_iteration::Int64=1000)
    pms = Dict{Int64, Any}()
    for i in keys(data_area)
        pms[i] = instantiate_dpm_model(data_area[i], model_type, build_method, ; alpha = alpha, tol = tol, max_iteration = max_iteration)
    end
    return pms
end




##
function share_solution!(data_area::Dict{Int64, <:Any})
    for i in keys(data_area) # sender subsystem
        for j in keys(data_area) # receiver subsystem
            if i != j && i in keys(data_area[j]["shared_primal"])
                shared_data = send_shared_data(i, j, data_area[i], serialize = false)
                    ### Communication ####
                receive_shared_data!(i, shared_data, data_area[j])
            end
        end
    end
end

##
function calc_mismatch!(data_area::Dict{Int64, <:Any}, p::Int64=2 )
    for i in keys(data_areas)
        calc_mismatch!(data_area[i],p)
    end
end

##
function update_flag_convergance!(data_area::Dict{Int64, <:Any}, tol::Float64)
    for i in keys(data_area)
        update_flag_convergance!(data_area[i], tol)
    end
end

##
function update_iteration!(data_area::Dict{Int64, <:Any})
    for i in keys(data_area)
        data_area[i]["iteration"] += 1
    end
end

##
function solve_local_model!(pms::Dict{Int, <:Any}, optimizer)
    for i in keys(pms)
        solve_subproblem!(pms[i], optimizer)
    end
end


##
calc_global_mismatch(data_area::Dict{Int, <:Any}, p::Int64=2) = norm([data_area[i]["mismatch"][end][string(i)] for i in keys(data_area)], p)

##
function check_flag_convergance(data_area::Dict{Int, <:Any})
    flag_convergance = reduce( & , [data_area[i]["flag_convergance"] for i in keys(data_area)])
    return flag_convergance
end




## Compare the distributed algorithm solutoin with PowerModels centralized solution
function compare_solution(data, data_area, model_type, optimizer)

    model_type = pf_formulation(model_type)

    # Update generator values
    for (i,gen) in data["gen"]
        area = data["bus"]["$(gen["gen_bus"])"]["area"]
        gen["pg"] = data_area[area]["gen"][i]["pg"]
    end

    # Solve Centralized OPF
    Central_solution = _PM.run_opf(data, model_type, optimizer)

    # Calculate objective function
    Obj_dist = _PM.calc_gen_cost(data)
    Obj_cent = Central_solution["objective"]

    # Calculate optimility gap
    Relative_Error = (Obj_dist - Obj_cent)/ Obj_cent * 100
    return Relative_Error
end
