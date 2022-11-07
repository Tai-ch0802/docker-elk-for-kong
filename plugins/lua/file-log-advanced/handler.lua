-- Copyright (C) Mashape, Inc.
local kong = kong
local ngx = ngx

local ffi = require "ffi"
local cjson = require "cjson"
local system_constants = require "lua_system_constants"
local serializer = require "kong.plugins.file-log-advanced.serializer"

local req_read_body = ngx.req.read_body
local req_get_body_data = ngx.req.get_body_data
local bit           = require "bit"



local ngx_timer = ngx.timer.at
local string_len = string.len
local O_CREAT = system_constants.O_CREAT()
local O_WRONLY = system_constants.O_WRONLY()
local O_APPEND = system_constants.O_APPEND()
local S_IRUSR = system_constants.S_IRUSR()
local S_IWUSR = system_constants.S_IWUSR()
local S_IRGRP = system_constants.S_IRGRP()
local S_IROTH = system_constants.S_IROTH()

local oflags = bit.bor(O_WRONLY, O_CREAT, O_APPEND)
local mode = bit.bor(S_IRUSR, S_IWUSR, S_IRGRP, S_IROTH)

ffi.cdef[[
int open(char * filename, int flags, int mode);
int write(int fd, void * ptr, int numbytes);
char *strerror(int errnum);
]]

-- fd tracking utility functions
local file_descriptors = {}

local function get_fd(conf_path)
  return file_descriptors[conf_path]
end

local function set_fd(conf_path, file_descriptor)
  file_descriptors[conf_path] = file_descriptor
end

local function string_to_char(str)
  return ffi.cast("uint8_t*", str)
end

-- Log to a file. Function used as callback from an nginx timer.
-- @param `premature` see OpenResty `ngx.timer.at()`
-- @param `conf`     Configuration table, holds http endpoint details
-- @param `message`  Message to be logged
local function log(premature, conf, message)
  if premature then return end

  local msg = cjson.encode(message).."\n"

  local fd = get_fd(conf.path)
  if not fd then
    fd = ffi.C.open(string_to_char(conf.path), oflags, mode)
    if fd < 0 then
      local errno = ffi.errno()
      ngx.log(ngx.ERR, "[file-log-advanced] failed to open the file: ", ffi.string(ffi.C.strerror(errno)))
    else
      set_fd(conf.path, fd)
    end
  end

  ffi.C.write(fd, string_to_char(msg), string_len(msg))
end


-- 日志处理器
local FileLogExtendedHandler = {
  VERSION  = "3.1.0",
  PRIORITY = 30,
}

function FileLogExtendedHandler:access(conf)
  ngx.ctx.file_log_extended_req_body = ""
  if conf.log_request then
    ngx.ctx.file_log_extended_req_body = kong.request.get_raw_body()
  end
end

function FileLogExtendedHandler:body_filter(conf)
  if conf.log_response then
    local ctx = kong.ctx.plugin;
    local chunk, eof = ngx.arg[1], ngx.arg[2];
    if not eof then
      ngx.ctx.file_log_extended_res_body = (ctx.response_body or "") .. (chunk or "")
    end
  end
end

function FileLogExtendedHandler:log(conf)
  local message = serializer.serialize(ngx)

  local ok, err = ngx_timer(0, log, conf, message)
  if not ok then
    ngx.log(ngx.ERR, "[file-log-advanced] failed to create timer: ", err)
  end

end

return FileLogExtendedHandler