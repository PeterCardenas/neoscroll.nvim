local time_tol = require("tests.time_tol")

local function set_up_wrapped_buffer(cursor_line)
  vim.o.columns = 80
  vim.api.nvim_command("enew | only")
  vim.cmd("setlocal wrap")

  local lines = {}
  for i = 1, 40 do
    local char = string.char(64 + ((i - 1) % 26) + 1)
    lines[i] = string.format("%02d ", i) .. string.rep(char, 220)
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { cursor_line or 10, 100 })
end

local function set_up_wrapped_eof_buffer()
  vim.o.columns = 80
  vim.api.nvim_command("enew | only")
  vim.cmd("setlocal wrap")

  local lines = {}
  for i = 1, 40 do
    local char = string.char(64 + ((i - 1) % 26) + 1)
    local width = i <= 36 and 220 or 20
    lines[i] = string.format("%02d ", i) .. string.rep(char, width)
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { 40, 0 })
  vim.cmd("normal! zb")
  vim.api.nvim_win_set_cursor(0, { 36, 100 })
end

describe("Wrapped lines", function()
  local neoscroll = require("neoscroll")
  local time = 100

  before_each(function()
    vim.go.scrolloff = 0
  end)

  it("scrolls the cursor and window by logical lines", function()
    neoscroll.setup({
      stop_eof = false,
      respect_scrolloff = false,
      cursor_scrolls_alone = false,
    })
    set_up_wrapped_buffer(10)

    local cursor_start = vim.fn.line(".")
    local window_start = vim.fn.line("w0")
    local col_start = vim.fn.col(".")
    local scroll_opts = { duration = time, move_cursor = true }

    neoscroll.scroll(3, scroll_opts)
    vim.wait(time + time_tol)
    assert.equals(cursor_start + 3, vim.fn.line("."))
    assert.equals(window_start + 3, vim.fn.line("w0"))
    assert.equals(col_start, vim.fn.col("."))

    neoscroll.scroll(-3, scroll_opts)
    vim.wait(time + time_tol)
    assert.equals(cursor_start, vim.fn.line("."))
    assert.equals(window_start, vim.fn.line("w0"))
    assert.equals(col_start, vim.fn.col("."))
  end)

  it("lets the cursor scroll alone by logical lines at EOF", function()
    neoscroll.setup({
      stop_eof = true,
      respect_scrolloff = false,
      cursor_scrolls_alone = true,
    })
    set_up_wrapped_eof_buffer()

    local cursor_start = vim.fn.line(".")
    local window_start = vim.fn.line("w0")

    neoscroll.scroll(1, { duration = time, move_cursor = true })
    vim.wait(time + time_tol)
    assert.equals(cursor_start + 1, vim.fn.line("."))
    assert.equals(window_start, vim.fn.line("w0"))
  end)

  it("scrolls wrapped lines with smoothscroll by logical lines", function()
    neoscroll.setup({
      stop_eof = false,
      respect_scrolloff = false,
      cursor_scrolls_alone = false,
    })
    set_up_wrapped_buffer(10)
    vim.cmd("setlocal smoothscroll")

    local cursor_start = vim.fn.line(".")
    local window_start = vim.fn.line("w0")

    neoscroll.scroll(1, { duration = time, move_cursor = true })
    vim.wait(time + time_tol)
    assert.equals(cursor_start + 1, vim.fn.line("."))
    assert.equals(window_start + 1, vim.fn.line("w0"))
  end)
end)
