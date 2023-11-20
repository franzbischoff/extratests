suppressPackageStartupMessages(library(tidymodels))
suppressPackageStartupMessages(library(censored))
suppressPackageStartupMessages(library(finetune))

skip_if_not_installed("finetune", minimum_version = "1.1.0.9001")
skip_if_not_installed("parsnip", minimum_version = "1.1.0.9003")
skip_if_not_installed("censored", minimum_version = "0.2.0.9000")
skip_if_not_installed("tune", minimum_version = "1.1.1.9001")
skip_if_not_installed("yardstick", minimum_version = "1.2.0.9001")
skip_if_not_installed("finetune", minimum_version = "1.1.0.9002")

test_that("race tuning (anova) survival models with static metric", {
  skip_if_not_installed("BradleyTerry2")
  skip_if_not_installed("flexsurv")

  # standard setup start -------------------------------------------------------

  set.seed(1)
  sim_dat <- prodlim::SimSurv(500) %>%
    mutate(event_time = Surv(time, event)) %>%
    select(event_time, X1, X2)

  set.seed(2)
  split <- initial_split(sim_dat)
  sim_tr <- training(split)
  sim_te <- testing(split)
  # high-ish number of bootstraps to simulate a case where the race gets down to
  # a single configuration
  sim_rs <- bootstraps(sim_tr, times = 20)

  time_points <- c(10, 1, 5, 15)

  mod_spec <-
    decision_tree(cost_complexity = tune()) %>%
    set_mode("censored regression")

  grid <- tibble(cost_complexity = 10^c(-10, -2, -1))

  gctrl <- control_grid(save_pred = TRUE)
  rctrl <- control_race(save_pred = TRUE, verbose_elim = FALSE, verbose = FALSE)

  # Racing with static metrics -------------------------------------------------

  stc_mtrc  <- metric_set(concordance_survival)

  set.seed(2193)
  aov_static_res <-
    mod_spec %>%
    tune_race_anova(
      event_time ~ X1 + X2,
      resamples = sim_rs,
      grid = grid,
      metrics = stc_mtrc,
      control = rctrl
    )

  num_final_aov <- unique(show_best(aov_static_res)$cost_complexity)

  # test structure of results --------------------------------------------------

  expect_false(".eval_time" %in% names(aov_static_res$.metrics[[1]]))

  expect_equal(
    names(aov_static_res$.predictions[[1]]),
    c(".pred_time", ".row", "cost_complexity", "event_time", ".config")
  )

  # test autoplot --------------------------------------------------------------

  expect_snapshot_plot(
    print(plot_race(aov_static_res)),
    "stc-aov-race-plot"
  )

  if (length(num_final_aov) > 1) {
    expect_snapshot_plot(
      print(autoplot(aov_static_res)),
      "stc-aov-race-2-times"
    )
  }

  # test metric collection -----------------------------------------------------

   exp_metric_sum <- tibble(
    cost_complexity = numeric(0),
    .metric = character(0),
    .estimator = character(0),
    mean = numeric(0),
    n = integer(0),
    std_err = numeric(0),
    .config = character(0)
  )
  exp_metric_all <- tibble(
    id = character(0),
    cost_complexity = numeric(0),
    .metric = character(0),
    .estimator = character(0),
    .estimate = numeric(0),
    .config = character(0)
  )

  ###

  aov_finished <-
    map_dfr(aov_static_res$.metrics, I) %>%
    count(.config) %>%
    filter(n == nrow(sim_rs))
  metric_aov_sum <- collect_metrics(aov_static_res)

  expect_equal(nrow(aov_finished), nrow(metric_aov_sum))
  expect_equal(metric_aov_sum[0,], exp_metric_sum)
  expect_true(all(metric_aov_sum$.metric == "concordance_survival"))

  ###

  metric_aov_all <- collect_metrics(aov_static_res, summarize = FALSE)
  expect_true(nrow(metric_aov_all) == nrow(aov_finished) * nrow(sim_rs))
  expect_equal(metric_aov_all[0,], exp_metric_all)
  expect_true(all(metric_aov_all$.metric == "concordance_survival"))
})

test_that("race tuning (anova) survival models with integrated metric", {
  skip_if_not_installed("BradleyTerry2")
  skip_if_not_installed("flexsurv")

  # standard setup start -------------------------------------------------------

  set.seed(1)
  sim_dat <- prodlim::SimSurv(500) %>%
    mutate(event_time = Surv(time, event)) %>%
    select(event_time, X1, X2)

  set.seed(2)
  split <- initial_split(sim_dat)
  sim_tr <- training(split)
  sim_te <- testing(split)
  # needs at least 3 bootstraps for the race to finish at a single configuration
  sim_rs <- bootstraps(sim_tr, times = 6)

  time_points <- c(10, 1, 5, 15)

  mod_spec <-
    decision_tree(cost_complexity = tune()) %>%
    set_mode("censored regression")

  # make it so there will probably be 2+ winners
  grid <- tibble(cost_complexity = 10^c(-10.1, -10.0, -2.0, -1.0))

  gctrl <- control_grid(save_pred = TRUE)
  rctrl <- control_race(save_pred = TRUE, verbose_elim = FALSE, verbose = FALSE)

  # Racing with integrated metrics ---------------------------------------------

  sint_mtrc <- metric_set(brier_survival_integrated)

  set.seed(2193)
  aov_integrated_res <-
    mod_spec %>%
    tune_race_anova(
      event_time ~ X1 + X2,
      resamples = sim_rs,
      grid = grid,
      metrics = sint_mtrc,
      eval_time = time_points,
      control = rctrl
    )

  num_final_aov <- unique(show_best(aov_integrated_res, eval_time = 5)$cost_complexity)

  # test structure of results --------------------------------------------------

  expect_false(".eval_time" %in% names(aov_integrated_res$.metrics[[1]]))

  expect_equal(
    names(aov_integrated_res$.predictions[[1]]),
    c(".pred", ".row", "cost_complexity", "event_time", ".config")
  )

  expect_true(is.list(aov_integrated_res$.predictions[[1]]$.pred))

  expect_equal(
    names(aov_integrated_res$.predictions[[1]]$.pred[[1]]),
    c(".eval_time", ".pred_survival", ".weight_censored")
  )

  expect_equal(
    aov_integrated_res$.predictions[[1]]$.pred[[1]]$.eval_time,
    time_points
  )

  # test autoplot --------------------------------------------------------------

  expect_snapshot_plot(
    print(plot_race(aov_integrated_res)),
    "int-aov-race-plot"
  )

  if (length(num_final_aov) > 1) {
    expect_snapshot_plot(
      print(autoplot(aov_integrated_res)),
      "int-aov-racing"
    )
  }

  # test metric collection

  exp_metric_sum <- tibble(
    cost_complexity = numeric(0),
    .metric = character(0),
    .estimator = character(0),
    mean = numeric(0),
    n = integer(0),
    std_err = numeric(0),
    .config = character(0)
  )
  exp_metric_all <- tibble(
    id = character(0),
    cost_complexity = numeric(0),
    .metric = character(0),
    .estimator = character(0),
    .estimate = numeric(0),
    .config = character(0)
  )

  ###

  aov_finished <-
    map_dfr(aov_integrated_res$.metrics, I) %>%
    count(.config) %>%
    filter(n == nrow(sim_rs))
  metric_aov_sum <- collect_metrics(aov_integrated_res)

  expect_equal(nrow(aov_finished), nrow(metric_aov_sum))
  expect_equal(metric_aov_sum[0,], exp_metric_sum)
  expect_true(all(metric_aov_sum$.metric == "brier_survival_integrated"))

  ###

  metric_aov_all <- collect_metrics(aov_integrated_res, summarize = FALSE)
  expect_true(nrow(metric_aov_all) == nrow(aov_finished) * nrow(sim_rs))
  expect_equal(metric_aov_all[0,], exp_metric_all)
  expect_true(all(metric_aov_all$.metric == "brier_survival_integrated"))

})

test_that("race tuning (anova) survival models with dynamic metrics", {
  skip_if_not_installed("BradleyTerry2")
  skip_if_not_installed("flexsurv")

  # standard setup start -------------------------------------------------------

  set.seed(1)
  sim_dat <- prodlim::SimSurv(500) %>%
    mutate(event_time = Surv(time, event)) %>%
    select(event_time, X1, X2)

  set.seed(2)
  split <- initial_split(sim_dat)
  sim_tr <- training(split)
  sim_te <- testing(split)
  sim_rs <- bootstraps(sim_tr, times = 20)

  time_points <- c(10, 1, 5, 15)

  mod_spec <-
    decision_tree(cost_complexity = tune()) %>%
    set_mode("censored regression")

  grid <- tibble(cost_complexity = 10^c(-10, -2, -1))

  gctrl <- control_grid(save_pred = TRUE)
  rctrl <- control_race(save_pred = TRUE, verbose_elim = FALSE, verbose = FALSE)
  rctrl_verb <- control_race(save_pred = TRUE, verbose_elim = TRUE, verbose = FALSE)

  # Racing with dynamic metrics ------------------------------------------------

  dyn_mtrc  <- metric_set(brier_survival)

  # use `capture.output()` instead of `expect_snapshot_test()`
  # https://github.com/tidymodels/extratests/pull/134#discussion_r1394534647
  aov_dyn_output <-
    capture.output({
      set.seed(2193)
      aov_dyn_res <-
        mod_spec %>%
        tune_race_anova(
          event_time ~ X1 + X2,
          resamples = sim_rs,
          grid = grid,
          metrics = dyn_mtrc,
          eval_time = time_points,
          control = rctrl_verb
        )
    },
    type = "message")

  num_final_aov <- unique(show_best(aov_dyn_res, eval_time = 5)$cost_complexity)

  # TODO add a test for checking the evaluation time in this message:
  # https://github.com/tidymodels/finetune/issues/81
  expect_true(any(grepl("Racing will minimize the brier_survival metric", aov_dyn_output)))

  # test structure of results --------------------------------------------------

  expect_true(".eval_time" %in% names(aov_dyn_res$.metrics[[1]]))

  expect_equal(
    names(aov_dyn_res$.predictions[[1]]),
    c(".pred", ".row", "cost_complexity", "event_time", ".config")
  )

  expect_true(is.list(aov_dyn_res$.predictions[[1]]$.pred))

  expect_equal(
    names(aov_dyn_res$.predictions[[1]]$.pred[[1]]),
    c(".eval_time", ".pred_survival", ".weight_censored")
  )

  expect_equal(
    aov_dyn_res$.predictions[[1]]$.pred[[1]]$.eval_time,
    time_points
  )

  # test autoplot --------------------------------------------------------------

  expect_snapshot_plot(
    print(plot_race(aov_dyn_res)),
    "dyn-aov-race-plot"
  )

  expect_snapshot_plot(
    print(autoplot(aov_dyn_res, eval_time = c(1, 5))),
    "dyn-aov-race-2-times"
  )

  expect_snapshot_warning(
    expect_snapshot_plot(
      print(autoplot(aov_dyn_res)),
      "dyn-aov-race-0-times"
    )
  )

  # test metric collection -----------------------------------------------------

    exp_metric_sum <- tibble(
    cost_complexity = numeric(0),
    .metric = character(0),
    .estimator = character(0),
    .eval_time = numeric(0),
    mean = numeric(0),
    n = integer(0),
    std_err = numeric(0),
    .config = character(0)
  )

  exp_metric_all <- tibble(
    id = character(0),
    cost_complexity = numeric(0),
    .metric = character(0),
    .estimator = character(0),
    .eval_time = numeric(0),
    .estimate = numeric(0),
    .config = character(0)
  )

  ###

  aov_finished <-
    map_dfr(aov_dyn_res$.metrics, I) %>%
    filter(.eval_time == 5) %>%
    count(.config) %>%
    filter(n == nrow(sim_rs))
  metric_aov_sum <- collect_metrics(aov_dyn_res)

  expect_equal(nrow(aov_finished) * length(time_points), nrow(metric_aov_sum))
  expect_equal(metric_aov_sum[0,], exp_metric_sum)
  expect_true(all(metric_aov_sum$.metric == "brier_survival"))

  ###

  metric_aov_all <- collect_metrics(aov_dyn_res, summarize = FALSE)
  expect_true(nrow(metric_aov_all) == nrow(aov_finished) * nrow(sim_rs) * length(time_points))
  expect_equal(metric_aov_all[0,], exp_metric_all)
  expect_true(all(metric_aov_all$.metric == "brier_survival"))

})

test_that("race tuning (anova) survival models with mixture of metric types", {
  skip_if_not_installed("BradleyTerry2")
  skip_if_not_installed("flexsurv")

  # standard setup start -------------------------------------------------------

  set.seed(1)
  sim_dat <- prodlim::SimSurv(500) %>%
    mutate(event_time = Surv(time, event)) %>%
    select(event_time, X1, X2)

  set.seed(2)
  split <- initial_split(sim_dat)
  sim_tr <- training(split)
  sim_te <- testing(split)
  sim_rs <- bootstraps(sim_tr, times = 30)

  time_points <- c(10, 1, 5, 15)

  mod_spec <-
    decision_tree(cost_complexity = tune()) %>%
    set_mode("censored regression")

  grid_winner <- tibble(cost_complexity = 10^c(-10, seq(-1.1, -1, length.out = 5)))
  grid_ties <- tibble(cost_complexity = 10^c(seq(-10.1, -10.0, length.out = 5)))

  gctrl <- control_grid(save_pred = TRUE)
  rctrl <- control_race(save_pred = TRUE, verbose_elim = FALSE, verbose = FALSE)
  rctrl_verb <- control_race(save_pred = TRUE, verbose_elim = TRUE, verbose = FALSE)

  # Racing with mixed metrics --------------------------------------------------

  mix_mtrc  <- metric_set(brier_survival, brier_survival_integrated, concordance_survival)

  aov_mixed_output <-
    capture.output({
      set.seed(2193)
      aov_mixed_res <-
        mod_spec %>%
        tune_race_anova(
          event_time ~ X1 + X2,
          resamples = sim_rs,
          grid = grid_winner,
          metrics = mix_mtrc,
          eval_time = time_points,
          control = rctrl_verb
        )
    },
    type = "message")

  num_final_aov <- unique(show_best(aov_mixed_res, metric = "brier_survival", eval_time = 5)$cost_complexity)

  expect_true(any(grepl("Racing will minimize the brier_survival metric at time 10", aov_mixed_output)))
  expect_true(length(num_final_aov) < nrow(grid_winner))

  # test structure of results --------------------------------------------------

  expect_true(".eval_time" %in% names(aov_mixed_res$.metrics[[1]]))

  expect_equal(
    names(aov_mixed_res$.predictions[[1]]),
    c(".pred", ".row", "cost_complexity", ".pred_time", "event_time", ".config")
  )

  expect_true(is.list(aov_mixed_res$.predictions[[1]]$.pred))

  expect_equal(
    names(aov_mixed_res$.predictions[[1]]$.pred[[1]]),
    c(".eval_time", ".pred_survival", ".weight_censored")
  )

  expect_equal(
    aov_mixed_res$.predictions[[1]]$.pred[[1]]$.eval_time,
    time_points
  )

  # test autoplot --------------------------------------------------------------

  expect_snapshot_plot(
    print(plot_race(aov_mixed_res)),
    "aov-race-plot"
  )

  # TODO make better plot at resolution of https://github.com/tidymodels/tune/issues/754
  # expect_snapshot_plot(
  #   print(autoplot(aov_mixed_res, eval_time = c(1, 5))),
  #   "mix-aov-race-2-times"
  # )

  # TODO make better plot at resolution of https://github.com/tidymodels/tune/issues/754
  # expect_snapshot_warning(
  #   expect_snapshot_plot(
  #     print(autoplot(aov_mixed_res)),
  #     "mix-aov-race-0-times"
  #   )
  # )

  # test metric collection -----------------------------------------------------

    exp_metric_sum <- tibble(
    cost_complexity = numeric(0),
    .metric = character(0),
    .estimator = character(0),
    .eval_time = numeric(0),
    mean = numeric(0),
    n = integer(0),
    std_err = numeric(0),
    .config = character(0)
  )

  exp_metric_all <- tibble(
    id = character(0),
    cost_complexity = numeric(0),
    .metric = character(0),
    .estimator = character(0),
    .eval_time = numeric(0),
    .estimate = numeric(0),
    .config = character(0)
  )
  num_metrics <- length(time_points) + 2

  ###

  aov_finished <-
    map_dfr(aov_mixed_res$.metrics, I) %>%
    filter(.eval_time == 5) %>%
    count(.config) %>%
    filter(n == nrow(sim_rs))
  metric_aov_sum <- collect_metrics(aov_mixed_res)

  expect_equal(nrow(aov_finished) * num_metrics, nrow(metric_aov_sum))
  expect_equal(metric_aov_sum[0,], exp_metric_sum)
  expect_true(sum(is.na(metric_aov_sum$.eval_time)) == 2 * nrow(aov_finished))
  expect_equal(as.vector(table(metric_aov_sum$.metric)), c(4L, 1L, 1L) * nrow(aov_finished))

  ###

  metric_aov_all <- collect_metrics(aov_mixed_res, summarize = FALSE)
  expect_true(nrow(metric_aov_all) == num_metrics * nrow(aov_finished) * nrow(sim_rs))
  expect_equal(metric_aov_all[0,], exp_metric_all)
  expect_true(sum(is.na(metric_aov_sum$.eval_time)) == 2 * nrow(aov_finished))
  expect_equal(as.vector(table(metric_aov_sum$.metric)), c(4L, 1L, 1L) * nrow(aov_finished))

  # test show_best() -----------------------------------------------------------

  expect_snapshot_warning(show_best(aov_mixed_res, metric = "brier_survival"))
  expect_snapshot(show_best(aov_mixed_res, metric = "brier_survival", eval_time = 1))
  expect_snapshot(
    show_best(aov_mixed_res, metric = "brier_survival", eval_time = c(1.001)),
    error = TRUE
  )
  expect_snapshot(
    show_best(aov_mixed_res, metric = "brier_survival", eval_time = c(1, 3)),
    error = TRUE
  )
  expect_snapshot(
    show_best(aov_mixed_res, metric = "brier_survival_integrated")
  )
})