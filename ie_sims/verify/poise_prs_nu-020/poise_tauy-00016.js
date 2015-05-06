{
  "preamble": "const pgrad = -5.2e-6; const rho_in = 1.1; const rho_out = rho_in + pgrad * 100; const datadir = \"data/poise_tauy-000016\"; const mu_p = 0.2; const tau_y = 0.00016; const m = 1.0e8; const max_iters = 150; const tol = 1e-6;",
  "datadir": "data/poise_tauy-000016",
  "dx": 1.0,
  "dt": 1.0,
  "ni": 50,
  "nj": 21,
  "rhoo": 1.0,
  "nu": 0.2,
  "nsteps": 10000,
  "col_f": "begin;
              curry_mrt_bingham_col_f!(lat, msm) = mrt_bingham_col_f!(lat, msm,
                vikhansky_relax_matrix, mu_p, tau_y, m, max_iters, tol,
                1.0e-11);
              return curry_mrt_bingham_col_f!;
            end",
  "bcs": [
    "north_bounce_back!",
    "south_bounce_back!",
    "begin;
        bind_west_pinlet!(lat) = west_pressure_inlet!(lat, rho_in);
        return bind_west_pinlet!;
      end",
      "begin;
        bind_east_poutlet!(lat) = east_pressure_outlet!(lat, rho_out);
        return bind_east_poutlet!;
      end"
  ],
  "callbacks": [
    "print_step_callback(25)"
  ],
  "postsim": "(msm::MultiscaleMap) -> begin
                writedlm(joinpath(datadir, \"ubar_profile.dsv\"),
                  extract_ubar_prof_callback(50)(msm), \",\");
              end"
}
