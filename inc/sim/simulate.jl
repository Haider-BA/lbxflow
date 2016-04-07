# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Debugging macros
macro _mdebug_mass_cons(opname, M, block)
  if @NDEBUG()
    return block;
  else
    return quote
      _init_mass = sum($M);
      $block;
      @mdebug($opname * ": ΔM = $(sum($M) - _init_mass)");
    end
  end
end

# Debugging macros
macro _checkdebug_mass_cons(opname, M, block, eps)
  if @NDEBUG()
    return block;
  else
    return quote
      _init_mass = sum($M);
      $block;
      @checkdebug(abs(sum($M) - _init_mass) < $eps,
                  $opname * ": ΔM = $(sum($M) - _init_mass)");
    end
  end
end

#! Stream particle densities
#!
#! \param lat Lattice to stream on
#! \param temp_f Temp lattice to store streamed particle distributions on
#! \param bounds Boundaries enclosing active streaming regions
function stream!(lat::Lattice, temp_f::Array{Float64,3}, bounds::Array{Int64,2})
  const nbounds = size(bounds, 2);
  #! Stream
  for r = 1:nbounds
    i_min, i_max, j_min, j_max = bounds[:,r];
    for j = j_min:j_max, i = i_min:i_max, k = 1:lat.n
      i_new = i + lat.c[1,k];
      j_new = j + lat.c[2,k];

      if i_new > i_max || j_new > j_max || i_new < i_min || j_new < j_min
        continue;
      end

      temp_f[k,i_new,j_new] = lat.f[k,i,j];
    end
  end

  copy!(lat.f, temp_f);
end

#! Stream particle densities in free surface conditions
#!
#! \param lat Lattice to stream on
#! \param temp_f Temp lattice to store streamed particle distributions on
#! \param bounds Boundaries enclosing active streaming regions
#! \param t Mass tracker
function stream!(lat::Lattice, temp_f::Array{Float64,3}, bounds::Array{Int64,2},
                 t::Tracker)
  const nbounds = size(bounds, 2);
  #! Stream
  for r = 1:nbounds
    i_min, i_max, j_min, j_max = bounds[:,r];
    for j = j_min:j_max, i = i_min:i_max
      if t.state[i,j] != GAS
        for k = 1:lat.n
          i_new = i + lat.c[1,k];
          j_new = j + lat.c[2,k];

          if (i_new > i_max || j_new > j_max || i_new < i_min || j_new < j_min 
              || t.state[i_new,j_new] == GAS)
            continue;
          end
          temp_f[k,i_new,j_new] = lat.f[k,i,j];
        end
      end
    end
  end

  copy!(lat.f, temp_f);
end

#! Stream particle densities around obstacles
#!
#! \param   lat             Lattice to stream on
#! \param   temp_f          Temp lattice to store streamed particle dists
#! \param   active_cells    Matrix of active flags
function stream!(lat::Lattice, temp_f::Array{Float64,3}, 
                 active_cells::Matrix{Bool})
  const ni, nj = size(lat.f, 2), size(lat.f, 3);

  #! Stream
  for j = 1:nj, i = 1:ni, k = 1:lat.n
    i_new = i + lat.c[1,k];
    j_new = j + lat.c[2,k];

    if (i_new < ni && j_new < nj && i_new > 1 && j_new > 1 
        && active_cells[i_new, j_new])
      temp_f[k,i_new,j_new] = lat.f[k,i,j];
    end
  end

  copy!(lat.f, temp_f);
end

#! Stream particle densities in free surface conditions
#!
#! \param   lat             Lattice to stream on
#! \param   temp_f          Temp lattice to store streamed particle dists
#! \param   active_cells    Matrix of active flags
#! \param   t               Mass tracker
function stream!(lat::Lattice, temp_f::Array{Float64,3}, 
                 active_cells::Matrix{Bool}, t::Tracker)
  const ni, nj = size(lat.f, 2), size(lat.f, 3);

  #! Stream
  for j = 1:nj, i = 1:ni, k = 1:lat.n
    i_new = i + lat.c[1,k];
    j_new = j + lat.c[2,k];

    if (i_new < ni && j_new < nj && i_new > 1 && j_new > 1 
        && active_cells[i_new, j_new] && t.state[i_new, j_new] != GAS)
      temp_f[k,i_new,j_new] = lat.f[k,i,j];
    end
  end

  copy!(lat.f, temp_f);
end

#! Simulate a single step
function sim_step!(sim::Sim, temp_f::Array{Float64,3},
                   sbounds::Matrix{Int64}, collision_f!::LBXFunction, 
                   cbounds::Matrix{Int64}, bcs!::Vector{LBXFunction})
  lat = sim.lat;
  msm = sim.msm;

  collision_f!(sim, cbounds);
  stream!(lat, temp_f, sbounds);

  for bc! in bcs!
    bc!(lat);
  end

  map_to_macro!(lat, msm);
end

#! Simulate a single step free surface flow step
function sim_step!(sim::FreeSurfSim, temp_f::Array{Float64,3},
                   sbounds::Matrix{Int64}, collision_f!::ColFunction, 
                   cbounds::Matrix{Int64}, 
                   bcs!::Vector{LBXFunction})
  lat   = sim.lat;
  msm   = sim.msm;
  t     = sim.tracker;

  const _init_mass = sum(t.M);
  # Algorithm should be:
  # 1.  mass transfer
  @_checkdebug_mass_cons("masstransfer!", t.M, masstransfer!(sim, sbounds), 1e-9);

  # 2.  stream
  @_checkdebug_mass_cons("stream!", t.M, stream!(lat, temp_f, sbounds, t), 1e-9);

  # 3.  reconstruct distribution functions from empty cells
  # 4.  reconstruct distribution functions along interface normal
  @_checkdebug_mass_cons("f_reconst!", t.M, for (i, j) in t.interfacels
    f_reconst!(sim, t, (i, j), collision_f!.feq_f, sim.rho_g);
  end, 1e-9);

  # 5.  particle collisions
  @_checkdebug_mass_cons("collision_f!", t.M, collision_f!(sim, cbounds), 1e-9);
  
  # 6.  enforce boundary conditions
  @_checkdebug_mass_cons("bcs!", t.M, for bc! in bcs!
    bc!(lat);
  end, 1e-9);

  # 7.  calculate macroscopic variables
  @_checkdebug_mass_cons("map_to_macro!", t.M, map_to_macro!(lat, msm), 1e-9);

  # 8.  update fluid fractions
  # 9.  update cell states
  @_checkdebug_mass_cons("update!", t.M, update!(sim, collision_f!.feq_f), 1e-9);

  @checkdebug(abs(_init_mass - sum(t.M)) < 1e-9, "whole step: ΔM = $(_init_mass - sum(t.M))");
end

#! Simulate a single step
function sim_step!(sim::Sim, temp_f::Array{Float64,3}, 
                   collision_f!::LBXFunction, active_cells::Matrix{Bool}, 
                   bcs!::Vector{LBXFunction})
  lat = sim.lat;
  msm = sim.msm;

  collision_f!(sim, active_cells);
  stream!(lat, temp_f, active_cells);

  for bc! in bcs!
    bc!(lat);
  end

  map_to_macro!(lat, msm);
end

#! Simulate a single step free surface flow step
function sim_step!(sim::FreeSurfSim, temp_f::Array{Float64,3},
                   collision_f!::ColFunction, active_cells::Matrix{Bool}, 
                   bcs!::Vector{LBXFunction})
  lat   = sim.lat;
  msm   = sim.msm;
  t     = sim.tracker;

  const _init_mass = sum(t.M);
  # Algorithm should be:
  # 1.  mass transfer
  @_checkdebug_mass_cons("masstransfer!", t.M, masstransfer!(sim, active_cells), 1e-9);

  # 2.  stream
  @_checkdebug_mass_cons("stream!", t.M, stream!(lat, temp_f, active_cells, t), 1e-9);

  # 3.  reconstruct distribution functions from empty cells
  # 4.  reconstruct distribution functions along interface normal
  @_checkdebug_mass_cons("f_reconst!", t.M,
  for (i, j) in t.interfacels #TODO maybe abstract out interface list...
    f_reconst!(sim, t, (i, j), collision_f!.feq_f, sim.rho_g);
  end, 1e-9);

  # 5.  particle collisions
  @_checkdebug_mass_cons("collision_f!", t.M, collision_f!(sim, active_cells), 1e-9);
  
  # 6.  enforce boundary conditions
  @_checkdebug_mass_cons("bcs!", t.M, for bc! in bcs!
    bc!(lat);
  end, 1e-9);

  # 7.  calculate macroscopic variables
  @_checkdebug_mass_cons("map_to_macro!", t.M, map_to_macro!(lat, msm), 1e-9);

  # 8.  update fluid fractions
  # 9.  update cell states
  @_checkdebug_mass_cons("update!", t.M, update!(sim, collision_f!.feq_f), 1e-9);

  @checkdebug(abs(_init_mass - sum(t.M)) < 1e-9, "whole step: ΔM = $(_init_mass - sum(t.M))");
end

#TODO clean up simulate! code with some kernal functions...
macro _report_and_exit(e, i)
  return quote
    const bt = catch_backtrace(); 
    showerror(STDERR, $e, bt);
    println();
    println("Showing backtrace:");
    Base.show_backtrace(STDERR, backtrace()); # display callstack
    println();
    warn("Simulation interrupted at step ", $i, "!");
    return $i;
  end
end

#! Run simulation
function simulate!(sim::AbstractSim, sbounds::Matrix{Int64},
                   collision_f!::LBXFunction, cbounds::Matrix{Int64},
                   bcs!::Vector{LBXFunction}, n_steps::Int, 
                   test_for_term::LBXFunction,
                   callbacks!::Vector{LBXFunction}, k::Int = 0)

  temp_f = copy(sim.lat.f);

  sim_step!(sim, temp_f, sbounds, collision_f!, cbounds, bcs!);

  for c! in callbacks!
    c!(sim, k+1);
  end

  prev_msm = MultiscaleMap(sim.msm);

  for i = k+2:n_steps
    try

      sim_step!(sim, temp_f, sbounds, collision_f!, cbounds, bcs!);

      for c! in callbacks!
        c!(sim, i);
      end

      # if returns true, terminate simulation
      if test_for_term(sim.msm, prev_msm)
        return i;
      end

      copy!(prev_msm.omega, sim.msm.omega);
      copy!(prev_msm.rho, sim.msm.rho);
      copy!(prev_msm.u, sim.msm.u);
    
    catch e

      @_report_and_exit(e, i);

    end
  end

  return n_steps;

end

#! Run simulation
function simulate!(sim::AbstractSim, sbounds::Matrix{Int64},
                   collision_f!::LBXFunction, cbounds::Matrix{Int64},
                   bcs!::Vector{LBXFunction}, n_steps::Int, 
                   test_for_term::LBXFunction,
                   steps_for_term::Int, callbacks!::Vector{LBXFunction}, 
                   k::Int = 0)

  temp_f = copy(sim.lat.f);

  sim_step!(sim, temp_f, sbounds, collision_f!, cbounds, bcs!);

  for c! in callbacks!
    c!(sim, k+1);
  end

  prev_msms = Vector{MultiscaleMap}(steps_for_term);
  for i=1:steps_for_term; prev_msms[i] = MultiscaleMap(sim.msm); end;

  for i = k+2:n_steps
    try

      sim_step!(sim, temp_f, sbounds, collision_f!, cbounds, bcs!);

      for c! in callbacks!
        c!(sim, i);
      end

      # if returns true, terminate simulation
      if test_for_term(sim.msm, prev_msms)
        return i;
      end
  
      const idx = i % steps_for_term + 1;
      copy!(prev_msms[idx].omega, sim.msm.omega);
      copy!(prev_msms[idx].rho,   sim.msm.rho);
      copy!(prev_msms[idx].u,     sim.msm.u);
    
    
    catch e

      @_report_and_exit(e, i);

    end

  end

  return n_steps;

end

#! Run simulation
function simulate!(sim::AbstractSim, sbounds::Matrix{Int64},
                   collision_f!::LBXFunction, cbounds::Matrix{Int64},
                   bcs!::Vector{LBXFunction}, n_steps::Int,
                   callbacks!::Vector{LBXFunction}, k::Int = 0)

  temp_f = copy(sim.lat.f);
  for i = k+1:n_steps
    try

      sim_step!(sim, temp_f, sbounds, collision_f!, cbounds, bcs!);

      for c! in callbacks!
        c!(sim, i);
      end

    
    catch e

      @_report_and_exit(e, i);

    end

  end

  return n_steps;

end

#! Run simulation
function simulate!(sim::AbstractSim, sbounds::Matrix{Int64},
                   collision_f!::LBXFunction, cbounds::Matrix{Int64},
                   bcs!::Vector{LBXFunction}, n_steps::Int, k::Int = 0)

  temp_f = copy(sim.lat.f);
  for i = k+1:n_step
    try; sim_step!(sim, temp_f, sbounds, collision_f!, cbounds, bcs!);
    catch e

      @_report_and_exit(e, i);

    end
  end

  return n_steps;

end

#! Run simulation
function simulate!(sim::AbstractSim, collision_f!::LBXFunction,
                   active_cells::Matrix{Bool},
                   bcs!::Vector{LBXFunction}, n_steps::Int, 
                   test_for_term::LBXFunction,
                   callbacks!::Vector{LBXFunction}, k::Int = 0)

  temp_f = copy(sim.lat.f);

  sim_step!(sim, temp_f, collision_f!, active_cells, bcs!);

  for c! in callbacks!
    c!(sim, k+1);
  end

  prev_msm = MultiscaleMap(sim.msm);

  for i = k+2:n_steps
    try

      sim_step!(sim, temp_f, collision_f!, active_cells, bcs!);

      for c! in callbacks!
        c!(sim, i);
      end

      # if returns true, terminate simulation
      if test_for_term(sim.msm, prev_msm)
        return i;
      end

      copy!(prev_msm.omega, sim.msm.omega);
      copy!(prev_msm.rho, sim.msm.rho);
      copy!(prev_msm.u, sim.msm.u);
    
    catch e

      @_report_and_exit(e, i);

    end
  end

  return n_steps;

end

#! Run simulation
function simulate!(sim::AbstractSim,
                   collision_f!::LBXFunction, active_cells::Matrix{Bool},
                   bcs!::Vector{LBXFunction}, n_steps::Int, 
                   test_for_term::LBXFunction,
                   steps_for_term::Int, callbacks!::Vector{LBXFunction}, 
                   k::Int = 0)

  temp_f = copy(sim.lat.f);

  sim_step!(sim, temp_f, collision_f!, active_cells, bcs!);

  for c! in callbacks!
    c!(sim, k+1);
  end

  prev_msms = Vector{MultiscaleMap}(steps_for_term);
  for i=1:steps_for_term; prev_msms[i] = MultiscaleMap(sim.msm); end;

  for i = k+2:n_steps
    try

      sim_step!(sim, temp_f, collision_f!, active_cells, bcs!);

      for c! in callbacks!
        c!(sim, i);
      end

      # if returns true, terminate simulation
      if test_for_term(sim.msm, prev_msms)
        return i;
      end
  
      const idx = i % steps_for_term + 1;
      copy!(prev_msms[idx].omega, sim.msm.omega);
      copy!(prev_msms[idx].rho,   sim.msm.rho);
      copy!(prev_msms[idx].u,     sim.msm.u);
    
    catch e

      @_report_and_exit(e, i);

    end
  end

  return n_steps;

end

#! Run simulation
function simulate!(sim::AbstractSim,
                   collision_f!::LBXFunction, active_cells::Matrix{Bool},
                   bcs!::Vector{LBXFunction}, n_steps::Int,
                   callbacks!::Vector{LBXFunction}, k::Int = 0)

  temp_f = copy(sim.lat.f);
  for i = k+1:n_steps
    try

      sim_step!(sim, temp_f, collision_f!, active_cells, bcs!);

      for c! in callbacks!
        c!(sim, i);
      end

    catch e

      @_report_and_exit(e, i);

    end
  end

  return n_steps;

end

#! Run simulation
function simulate!(sim::AbstractSim,
                   collision_f!::LBXFunction, active_cells::Matrix{Bool},
                   bcs!::Vector{LBXFunction}, n_steps::Int, k::Int = 0)

  temp_f = copy(sim.lat.f);
  for i = k+1:n_step
    try; sim_step!(sim, temp_f, collision_f!, active_cells, bcs!);
    catch e

      @_report_and_exit(e, i);

    end
  end

  return n_steps;

end
