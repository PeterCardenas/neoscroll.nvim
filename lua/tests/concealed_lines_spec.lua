local time_tol = require("tests.time_tol")

local function setup_conceal_per_line_buffer(total_lines, conceal_start, conceal_end, cursor_line)
  vim.cmd("enew | only")

  local lines = {}
  for i = 1, total_lines do
    lines[i] = "line " .. i
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

  local ns = vim.api.nvim_create_namespace("neoscroll_test_conceal_per_line")
  for i = conceal_start, conceal_end do
    vim.api.nvim_buf_set_extmark(0, ns, i - 1, 0, { conceal_lines = "" })
  end

  vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
end

local function setup_conceal_range_buffer(total_lines, conceal_start, conceal_end, cursor_line)
  vim.cmd("enew | only")

  local lines = {}
  for i = 1, total_lines do
    lines[i] = "line " .. i
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

  local ns = vim.api.nvim_create_namespace("neoscroll_test_conceal_range")
  vim.api.nvim_buf_set_extmark(
    0,
    ns,
    conceal_start - 1,
    0,
    { conceal_lines = "", end_row = conceal_end }
  )

  vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
end

local function setup_streamed_markdown_injection_buffer(total_lines, cursor_line)
  vim.o.columns = 120
  vim.cmd("enew | only")
  vim.cmd("setlocal wrap")

  local ns = vim.api.nvim_create_namespace("neoscroll_test_stream_injections")
  local chunk = {}
  local chunk_size = 200
  for i = 1, total_lines do
    chunk[#chunk + 1] = string.format("%05d %s", i, string.rep("m", 1800))
    if #chunk == chunk_size or i == total_lines then
      local start = vim.api.nvim_buf_line_count(0)
      vim.api.nvim_buf_set_lines(0, -1, -1, false, chunk)
      for j = 1, #chunk do
        vim.api.nvim_buf_set_extmark(0, ns, start + j - 1, 0, {
          virt_text = { { "[md-inject]", "Comment" } },
          virt_text_pos = "eol",
        })
      end
      chunk = {}
    end
  end

  vim.cmd("setlocal foldmethod=manual foldenable foldlevel=0")
  for i = 40, total_lines - 200, 10 do
    vim.cmd(string.format("silent! %d,%dfold", i, i + 5))
  end
  vim.cmd("normal! zM")
  vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
  vim.cmd("normal! zz")
end

local function scroll_with_stats(neoscroll, lines, duration)
  local scroll = require("neoscroll.scroll")
  local uv = vim.uv or vim.loop
  local t0 = uv.hrtime()

  neoscroll.scroll(lines, { duration = duration, move_cursor = true })
  local done = vim.wait(duration + time_tol + 5000, function()
    return not scroll.scrolling
  end, 1)

  return {
    done = done,
    elapsed_ms = (uv.hrtime() - t0) / 1e6,
    line = vim.fn.line("."),
  }
end

describe("Concealed lines", function()
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

  it("does not stall when entering very long concealed runs", function()
    setup_conceal_per_line_buffer(90000, 100, 80000, 90)
    local stats = scroll_with_stats(neoscroll, 20, 120)
    assert.is_true(stats.done)
    assert.is_true(stats.elapsed_ms < 350)
    assert.is_true(stats.line > 80000)
  end)

  it("skips full ranged conceal_lines extmarks", function()
    setup_conceal_range_buffer(3000, 100, 2200, 95)
    local stats = scroll_with_stats(neoscroll, 20, 140)
    assert.is_true(stats.done)
    assert.is_true(stats.line > 2200)
  end)

  it("stays responsive with streamed markdown-like injections and many folds", function()
    setup_streamed_markdown_injection_buffer(25000, 10000)
    local stats = scroll_with_stats(neoscroll, 300, 220)
    assert.is_true(stats.done)
    assert.is_true(stats.elapsed_ms < 420)
    assert.is_true(stats.line > 10000)
  end)
end)
