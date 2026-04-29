local time_tol = require("tests.time_tol")

local function set_up_pathological_buffer(cursor_row)
  vim.o.columns = 120
  vim.api.nvim_command("enew | only")
  vim.cmd("setlocal wrap smoothscroll")
  vim.cmd("setlocal foldenable foldmethod=manual foldlevel=0")

  local lines = {}
  for i = 1, 5000 do
    lines[i] = string.rep("x", 12000) .. tostring(i)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  for i = 50, 4990, 10 do
    vim.cmd(string.format("silent! %d,%dfold", i, i + 4))
  end
  vim.cmd("normal! zM")
  vim.api.nvim_win_set_cursor(0, { cursor_row or 2500, 0 })
  vim.cmd("normal! zz")
end

local function capture_scroll_stats(neoscroll, lines, duration)
  local scroll = require("neoscroll.scroll")
  local uv = vim.uv or vim.loop
  local orig_scroll_one_line = scroll.scroll_one_line
  local calls = 0

  scroll.scroll_one_line = function(self, ...)
    calls = calls + 1
    return orig_scroll_one_line(self, ...)
  end

  local t0 = uv.hrtime()
  neoscroll.scroll(lines, { duration = duration, move_cursor = true })
  local startup_ms = (uv.hrtime() - t0) / 1e6
  local done = vim.wait(duration + time_tol + 1000, function()
    return not scroll.scrolling
  end, 1)
  local total_ms = (uv.hrtime() - t0) / 1e6

  scroll.scroll_one_line = orig_scroll_one_line
  return {
    calls = calls,
    done = done,
    startup_ms = startup_ms,
    total_ms = total_ms,
  }
end

describe("Deterministic smoothscroll screenline mode", function()
  local neoscroll = require("neoscroll")

  before_each(function()
    neoscroll.setup({
      stop_eof = false,
      respect_scrolloff = false,
      cursor_scrolls_alone = false,
      hide_cursor = false,
      easing = "linear",
    })
    vim.go.scrolloff = 0
  end)

  it("uses requested screenline steps on pathological wrapped+folded buffers", function()
    set_up_pathological_buffer(2500)
    local requested = 20
    local stats = capture_scroll_stats(neoscroll, requested, 300)
    assert.is_true(stats.done)
    assert.equals(requested, stats.calls)
    assert.is_true(stats.startup_ms < 20)
  end)

  it("keeps duration in a tight envelope for deterministic steps", function()
    set_up_pathological_buffer(2500)
    local duration = 300
    local stats = capture_scroll_stats(neoscroll, 20, duration)
    assert.is_true(stats.done)
    assert.is_true(stats.total_ms >= duration - 50)
    assert.is_true(stats.total_ms <= duration + time_tol + 250)
  end)

  it("completes single-step scrolls without long timer tail", function()
    set_up_pathological_buffer(2500)
    local stats = capture_scroll_stats(neoscroll, 1, 110)
    assert.is_true(stats.done)
    assert.equals(1, stats.calls)
    assert.is_true(stats.total_ms < 500)
  end)

  it("stops immediately at the top edge", function()
    set_up_pathological_buffer(1)
    local stats = capture_scroll_stats(neoscroll, -40, 300)
    assert.is_true(stats.done)
    assert.equals(0, stats.calls)
    assert.is_true(stats.total_ms < 100)
  end)
end)
