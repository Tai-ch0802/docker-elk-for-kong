local pl_utils = require "pl.utils"
local typedefs = require "kong.db.schema.typedefs"

local PLUGIN_NAME = "file-log-advanced"

local schema = {
  name = PLUGIN_NAME,
  fields = {
    -- the 'fields' array is the top-level entry with fields defined by Kong
    { protocols = typedefs.protocols },
    { config = {
        -- The 'config' record is the custom part of the plugin schema
        type = "record",
        fields = {
          { path = { type = "string", required = true, match = [[^[^*&%%\`]+$]], err = "not a valid filename", }, },
          { log_request = { type = "boolean", default = true }, },
          { log_response = { type = "boolean", default = false }, },
        },
      },
    },
  },
}

return schema