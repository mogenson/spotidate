--- Print a formatted string to the console.
---@param fmt string Format string (defaults to "" if nil)
---@param ... any Values to interpolate into the format string
function printf(fmt, ...)
    print(string.format(fmt or "", ...))
end
