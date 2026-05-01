local config = require("neoscroll.config").opts
local ctrl_y = vim.api.nvim_replace_termcodes("<C-y>", false, false, true)
local ctrl_e = vim.api.nvim_replace_termcodes("<C-e>", false, false, true)

-- stylua: ignore start
local easing_function = {
  quadratic = function(x) return 1 - math.pow(1 - x, 1 / 2) end,
  cubic = function(x) return 1 - math.pow(1 - x, 1 / 3) end,
  quartic = function(x) return 1 - math.pow(1 - x, 1 / 4) end,
  quintic = function(x) return 1 - math.pow(1 - x, 1 / 5) end,
  circular = function(x) return 1 - math.pow(1 - x * x, 1 / 2) end,
  sine = function(x) return 2 * math.asin(x) / math.pi end,
}
-- stylua: ignore end

local function create_scroll_func(scroll_args, winid)
  local scroll_func = function()
    vim.cmd.normal({ bang = true, args = { scroll_args } })
  end
  -- Avoid vim.api.nvim_win_call if we don't need it
  if winid == 0 then
    return scroll_func
  else
    return function()
      vim.api.nvim_win_call(winid, scroll_func)
    end
  end
end

local conceal_lookup_limit = 512
local conceal_fallback_probe_interval = 16

---@param mark table
---@return integer | nil, integer | nil
local function conceal_span_from_mark(mark)
  local details = mark[4]
  if not details or details.conceal_lines == nil then
    return nil, nil
  end

  local start_line = mark[2] + 1
  local end_line = details.end_row ~= nil and details.end_row or start_line
  if end_line < start_line then
    end_line = start_line
  end
  return start_line, end_line
end

---@param bufnr integer
---@param lnum integer 1-based line number
---@return integer | nil, integer | nil
local function conceal_span_on_line(bufnr, lnum)
  local marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    -1,
    { lnum - 1, 0 },
    { lnum - 1, -1 },
    { details = true }
  )
  for _, mark in ipairs(marks) do
    local start_line, end_line = conceal_span_from_mark(mark)
    if start_line and lnum >= start_line and lnum <= end_line then
      return start_line, end_line
    end
  end
  return nil, nil
end

---@param bufnr integer
---@param lnum integer 1-based line number
---@return integer | nil, integer | nil
local function conceal_span_covering_line(bufnr, lnum)
  local prior_marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    -1,
    { lnum - 1, -1 },
    { 0, 0 },
    { details = true, limit = conceal_lookup_limit }
  )
  for _, mark in ipairs(prior_marks) do
    local start_line, end_line = conceal_span_from_mark(mark)
    if start_line and lnum >= start_line and lnum <= end_line then
      return start_line, end_line
    end
  end

  return nil, nil
end

---@param bufnr integer
---@param lnum integer 1-based line number
---@param conceal_state table | nil
---@return integer | nil, integer | nil
local function conceal_span_at_line(bufnr, lnum, conceal_state)
  if conceal_state then
    local known_start = conceal_state.range_start
    local known_end = conceal_state.range_end
    if known_start and known_end then
      if lnum >= known_start and lnum <= known_end then
        return known_start, known_end
      end
      if lnum > known_end or lnum < known_start then
        conceal_state.range_start = nil
        conceal_state.range_end = nil
      end
    end
  end

  local start_line, end_line = conceal_span_on_line(bufnr, lnum)
  if start_line then
    if conceal_state then
      conceal_state.range_start = start_line
      conceal_state.range_end = end_line
      conceal_state.miss_count = 0
    end
    return start_line, end_line
  end

  if conceal_state then
    conceal_state.miss_count = (conceal_state.miss_count or 0) + 1
    local should_probe = conceal_state.miss_count == 1
      or conceal_state.miss_count % conceal_fallback_probe_interval == 0
    if not should_probe then
      return nil, nil
    end
  end

  start_line, end_line = conceal_span_covering_line(bufnr, lnum)
  if start_line and conceal_state then
    conceal_state.range_start = start_line
    conceal_state.range_end = end_line
    conceal_state.miss_count = 0
  end
  return start_line, end_line
end

---@param bufnr integer
---@param lnum integer 1-based line number
---@param conceal_state table | nil
---@return boolean
local function is_line_concealed(bufnr, lnum, conceal_state)
  local start_line, _ = conceal_span_at_line(bufnr, lnum, conceal_state)
  return start_line ~= nil
end

---@param bufnr integer
---@param start_line integer
---@param direction integer
---@param max_line integer
---@param conceal_state table | nil
---@return integer | nil
local function find_next_unconcealed_line(bufnr, start_line, direction, max_line, conceal_state)
  if not is_line_concealed(bufnr, start_line, conceal_state) then
    return start_line
  end

  local function concealed(lnum)
    return is_line_concealed(bufnr, lnum, conceal_state)
  end

  if direction > 0 then
    local concealed_line = start_line
    local probe = start_line
    local step = 1
    while probe < max_line do
      local next_probe = math.min(max_line, probe + step)
      if not concealed(next_probe) then
        probe = next_probe
        break
      end
      concealed_line = next_probe
      probe = next_probe
      step = step * 2
    end

    if concealed(probe) then
      return nil
    end

    local left = concealed_line
    local right = probe
    while right - left > 1 do
      local mid = math.floor((left + right) / 2)
      if concealed(mid) then
        left = mid
      else
        right = mid
      end
    end
    return right
  end

  local concealed_line = start_line
  local probe = start_line
  local step = 1
  while probe > 1 do
    local next_probe = math.max(1, probe - step)
    if not concealed(next_probe) then
      probe = next_probe
      break
    end
    concealed_line = next_probe
    probe = next_probe
    step = step * 2
  end

  if concealed(probe) then
    return nil
  end

  local left = probe
  local right = concealed_line
  while right - left > 1 do
    local mid = math.floor((left + right) / 2)
    if concealed(mid) then
      right = mid
    else
      left = mid
    end
  end
  return left
end

local scroll = {
  target_line = 0,
  relative_line = 0,
  initial_cursor_win_line = nil,
  scrolling = false,
  continuous_scroll = false,
  screenline_mode = false,
  timer = vim.loop.new_timer(),
}

function scroll:new(lines, opts)
  local o = { lines = lines, opts = opts }
  setmetatable(o, self)
  self.__index = self
  return o
end

function scroll:lines_to_scroll()
  return self.target_line - self.relative_line
end

-- Hide/unhide cursor during scrolling for a better visual effect
function scroll:hide_cursor()
  if vim.o.termguicolors and vim.o.guicursor ~= "" then
    self.guicursor = vim.o.guicursor
    vim.o.guicursor = "a:NeoscrollHiddenCursor"
  end
end

function scroll:unhide_cursor()
  if vim.o.guicursor == "a:NeoscrollHiddenCursor" then
    vim.o.guicursor = self.guicursor
  end
end

---scrolling constructor
function scroll:set_up()
  if config.pre_hook ~= nil then
    config.pre_hook(self.opts.info)
  end
  -- Start scrolling
  self.scrolling = true
  -- Hide cursor line
  if config.hide_cursor and self.opts.move_cursor then
    self:hide_cursor()
  end
  -- Disable events
  if next(config.ignored_events) ~= nil then
    vim.opt.eventignore:append(config.ignored_events)
  end
  -- Performance mode
  local performance_mode = vim.b.neoscroll_performance_mode or vim.g.neoscroll_performance_mode
  if performance_mode and self.opts.move_cursor then
    -- Disable treesitter highlighting
    if vim.g.loaded_nvim_treesitter then
      local ok = pcall(vim.treesitter.stop)
      if not ok then
        vim.cmd("TSBufDisable highlight")
      end
    end
    vim.bo.syntax = "OFF"
  end
  -- Assign number of lines to scroll
  self.target_line = self.lines
  self.conceal_state = { range_start = nil, range_end = nil, miss_count = 0 }
end

---scrolling destructor
function scroll:tear_down()
  self.timer:stop()

  -- Unhide cursor
  if config.hide_cursor == true and self.opts.move_cursor then
    self:unhide_cursor()
  end
  --Performance mode
  local performance_mode = vim.b.neoscroll_performance_mode or vim.g.neoscroll_performance_mode
  if performance_mode and self.opts.move_cursor then
    vim.bo.syntax = "ON"
    if vim.g.loaded_nvim_treesitter then
      local ok = pcall(vim.treesitter.start)
      if not ok then
        vim.cmd("TSBufEnable highlight")
      end
    end
  end
  if config.post_hook ~= nil then
    config.post_hook(self.opts.info)
  end
  -- Reenable events
  if next(config.ignored_events) ~= nil then
    vim.opt.eventignore:remove(config.ignored_events)
  end

  self.relative_line = 0
  self.target_line = 0
  self.conceal_state = nil
  self.scrolling = false
  self.continuous_scroll = false
  self.screenline_mode = false
end

---Compute current time step of animation
---@param lines_to_scroll integer Number of lines left to scroll
---@return integer
function scroll:compute_time_step(lines_to_scroll)
  local easing = self.opts.easing or config.easing_function or config.easing
  local ef = easing_function[easing]
  local duration = self.opts.duration or 0
  -- lines_to_scroll should always be positive
  -- If there's less than one line to scroll time_step doesn't matter
  if lines_to_scroll < 1 then
    return 1000
  end
  local lines_range = math.abs(self.lines)
  if lines_range <= 1 then
    return math.max(1, math.floor(duration + 0.5))
  end
  local time_step
  -- If not yet in range return average time-step
  if not ef then
    time_step = math.floor(duration / (lines_range - 1) + 0.5)
  elseif lines_to_scroll >= lines_range then
    time_step = math.floor(duration * ef(1 / lines_range) + 0.5)
  else
    local x1 = (lines_range - lines_to_scroll) / lines_range
    local x2 = (lines_range - lines_to_scroll + 1) / lines_range
    time_step = math.floor(duration * (ef(x2) - ef(x1)) + 0.5)
  end
  if time_step == 0 then
    time_step = 1
  end
  return time_step
end

---scroll one line in the given direction
---@param lines_to_scroll integer
---@param scroll_window boolean
---@param scroll_cursor boolean
---@return boolean
function scroll:scroll_one_line(lines_to_scroll, scroll_window, scroll_cursor)
  if lines_to_scroll == 0 then
    error("lines_to_scroll cannot be zero")
  end
  local initial_winline = vim.api.nvim_win_call(self.opts.winid, vim.fn.winline)
  local initial_cursor_line = vim.api.nvim_win_get_cursor(self.opts.winid)[1]
  local direction = lines_to_scroll > 0 and 1 or -1
  local window_scroll_cmd = direction > 0 and ctrl_e or ctrl_y
  local screenline_cursor_scroll_cmd = direction > 0 and "gj" or "gk"

  local function run_scroll_cmd(scroll_cmd)
    if scroll_cmd == "" then
      return true
    end
    local scroll_func = create_scroll_func(scroll_cmd, self.opts.winid)
    return pcall(scroll_func) ---@diagnostic disable-line
  end

  if self.screenline_mode then
    local scroll_args
    if scroll_window and scroll_cursor then
      scroll_args = window_scroll_cmd .. screenline_cursor_scroll_cmd
    elseif scroll_window then
      scroll_args = window_scroll_cmd
    elseif scroll_cursor then
      scroll_args = screenline_cursor_scroll_cmd
    else
      return false
    end

    local success = run_scroll_cmd(scroll_args)
    if not success then
      return false
    end

    self.relative_line = self.relative_line + direction
    return true
  end

  local cursor_line_wraps = vim.api.nvim_win_call(self.opts.winid, function()
    if not vim.wo.wrap then
      return false
    end
    local wininfo = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
    local text_width = vim.api.nvim_win_get_width(0) - wininfo.textoff
    return text_width > 0 and vim.fn.virtcol("$") - 1 > text_width
  end)
  local cursor_scroll_cmd
  if cursor_line_wraps then
    cursor_scroll_cmd = lines_to_scroll > 0 and "j" or "k"
  else
    cursor_scroll_cmd = lines_to_scroll > 0 and "gj" or "gk"
  end

  if cursor_line_wraps then
    if scroll_window and not run_scroll_cmd(window_scroll_cmd) then
      return false
    end
    local cursor_line_after_window_scroll = vim.api.nvim_win_get_cursor(self.opts.winid)[1]
    local should_scroll_cursor = scroll_cursor
      and (not scroll_window or cursor_line_after_window_scroll == initial_cursor_line)
    if should_scroll_cursor and not run_scroll_cmd(cursor_scroll_cmd) then
      return false
    end
  else
    local cursor_scroll_args = scroll_cursor and cursor_scroll_cmd or ""
    local window_scroll_args = scroll_window and window_scroll_cmd or ""
    local scroll_args = window_scroll_args .. cursor_scroll_args
    local success = run_scroll_cmd(scroll_args)
    if not success then
      return false
    end
  end
  local scrolled_lines = lines_to_scroll > 0 and 1 or -1

  -- Skip concealed lines (conceal_lines extmarks with zero display height).
  -- The cursor can land on these via gj/gk or scrolloff enforcement.
  local bufnr = vim.api.nvim_win_get_buf(self.opts.winid)
  local function skip_concealed_cursor_lines()
    local cursor = vim.api.nvim_win_get_cursor(self.opts.winid)
    local cur_line = cursor[1]
    if not is_line_concealed(bufnr, cur_line, self.conceal_state) then
      return
    end

    local max_line = vim.api.nvim_buf_line_count(bufnr)
    local target_line =
      find_next_unconcealed_line(bufnr, cur_line, direction, max_line, self.conceal_state)
    if not target_line or target_line == cur_line then
      return
    end
    while
      target_line >= 1
      and target_line <= max_line
      and is_line_concealed(bufnr, target_line, self.conceal_state)
    do
      target_line = target_line + direction
    end
    if target_line < 1 or target_line > max_line then
      return
    end

    local ok = pcall(vim.api.nvim_win_set_cursor, self.opts.winid, { target_line, cursor[2] })
    if not ok then
      pcall(vim.api.nvim_win_set_cursor, self.opts.winid, { target_line, 0 })
    end
  end

  skip_concealed_cursor_lines()

  if scroll_cursor and scroll_window and not cursor_line_wraps then
    -- Correct for wrapped lines
    local winline = vim.api.nvim_win_call(self.opts.winid, vim.fn.winline)
    local lines_behind = winline - self.initial_cursor_win_line
    if lines_to_scroll > 0 then
      lines_behind = -lines_behind
    end
    if lines_behind > 0 then
      local cursor_args = string.rep(cursor_scroll_cmd, lines_behind)
      local catchup_scroll = create_scroll_func(cursor_args, self.opts.winid)
      local success, _ = pcall(catchup_scroll) ---@diagnostic disable-line
      if not success then
        return false
      end
      skip_concealed_cursor_lines()
    end
  end

  -- If the cursor is still on the same line we can use the change in window line
  -- to calculate the lines we have scrolled more accurately (not affected by wrapped lines)
  local cursor_line = vim.api.nvim_win_get_cursor(self.opts.winid)[1]
  if cursor_line == initial_cursor_line then
    local final_winline = vim.api.nvim_win_call(self.opts.winid, vim.fn.winline)
    scrolled_lines = initial_winline - final_winline
  end

  -- If we have past our target line (e.g. when forced by  wrapped lines) set lines_to_scroll
  -- to 1 to trigger scroll:tear_down(). Otherwise it will start scrolling backwards and
  -- potentially run into an infinite loop
  local new_relative_line = self.relative_line + scrolled_lines
  local new_lines_to_scroll = self.target_line - new_relative_line
  local target_overshot = lines_to_scroll * new_lines_to_scroll < 0
  if target_overshot then
    self.relative_line = self.target_line
  else
    self.relative_line = self.relative_line + scrolled_lines
  end
  return true
end

return scroll
