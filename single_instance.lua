local mp    = require 'mp'
local msg   = require 'mp.msg'
local utils = require 'mp.utils'

local ipc_socket_path
if package.config:sub(1,1) == "\" then
    ipc_socket_path = "\\\\.\\pipe\\mpvsocket"
else
    ipc_socket_path = "/tmp/mpvsocket"
end

local function escape_json_str(str)
    if not str then return "" end
    return (str:gsub("\\", "\\\\")
               :gsub("\"", "\\\""))
end

local function get_full_path()
    local path = mp.get_property("path") or ""
    return path
end

local function try_connect_pipe(path)
    local f = io.open(path, "w")
    if f then
        f:close()
        return true
    end
    return false
end

local function send_file_to_main(path, filepath)
    local escaped = escape_json_str(filepath or "")
    local json = string.format(
        '{\"command\": [\"loadfile\", \"%s\", \"replace\"]}',
        escaped
    )

    local f = io.open(path, "w")
    if not f then
        msg.error("Could not connect to IPC pipe: " .. path)
        return false
    end

    f:write(json .. "\n")
    f:close()

    msg.info("Sent file to main MPV instance: " .. filepath)
    return true
end

local function create_ipc_server(path)
    mp.set_property("input-ipc-server", path)
    msg.info("Created IPC server: " .. path)
end

local is_main_instance = false
if try_connect_pipe(ipc_socket_path) then
    is_main_instance = false
    msg.info("Another MPV instance detected. Acting as secondary.")
else
    create_ipc_server(ipc_socket_path)
    is_main_instance = true
    msg.info("No other instance found. Acting as main MPV.")
end

mp.register_event("start-file", function()
    local filepath = get_full_path()

    if filepath == "" then
        msg.warn("No valid file path. Idle mode.")
        return
    end

    msg.info("Opening file: " .. filepath)

    if is_main_instance then
        msg.info("Main instance: playing normally.")
    else
        msg.info("Secondary instance: forwarding file → quitting.")

        if send_file_to_main(ipc_socket_path, filepath) then
            mp.add_timeout(0.1, function()
                mp.commandv("quit")
            end)
        else
            msg.error("Failed to send file. Converting to main instance.")
            create_ipc_server(ipc_socket_path)
            is_main_instance = true
        end
    end
end)
