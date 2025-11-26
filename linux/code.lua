local mp    = require "mp"
local msg   = require "mp.msg"
local utils = require "mp.utils"

-- Debian/Linux socket path
local ipc_socket_path = "/tmp/mpvsocket"

------------------------------------------------------
-- Escape JSON helper
------------------------------------------------------
local function escape_json_str(str)
    if not str then return "" end
    return (str:gsub("\\", "\\\\"):gsub("\"", "\\\""))
end

------------------------------------------------------
-- Get full file path
------------------------------------------------------
local function get_full_path()
    return mp.get_property("path") or ""
end

------------------------------------------------------
-- Check if socket exists using utils.file_info()
------------------------------------------------------
local function socket_exists(path)
    local info = utils.file_info(path)
    return info and info.is_socket
end

------------------------------------------------------
-- Send JSON command to main instance via IPC
------------------------------------------------------
local function send_file_to_main(socket, file)
    local escaped = escape_json_str(file or "")
    local json = string.format(
        '{ "command": ["loadfile", "%s", "replace"] }',
        escaped
    )

    msg.info("Sending via IPC: " .. json)

    local res = mp.command_native({
        name = "subprocess",
        args = { "socat", "-", "UNIX-CONNECT:" .. socket },
        stdin_data = json .. "\n",
        capture_stdout = false,
        capture_stderr = false
    })

    if res.status == 0 then
        msg.info("Sent file to main instance")
        return true
    else
        msg.error("IPC send failed")
        return false
    end
end

------------------------------------------------------
-- Create IPC server
------------------------------------------------------
local function create_ipc_server(path)
    mp.set_property("input-ipc-server", path)
    msg.info("Created IPC server on " .. path)
end

------------------------------------------------------
-- Determine main or secondary instance
------------------------------------------------------
local is_main_instance = false

if socket_exists(ipc_socket_path) then
    msg.info("Existing socket found → Secondary instance")
    is_main_instance = false
else
    msg.info("No socket found → This is main instance")
    create_ipc_server(ipc_socket_path)
    is_main_instance = true
end

------------------------------------------------------
-- Event: start-file
------------------------------------------------------
mp.register_event("start-file", function()
    local filepath = get_full_path()

    if filepath == "" then
        msg.warn("Invalid file path")
        return
    end

    if is_main_instance then
        msg.info("Main instance: playing normally")
    else
        msg.info("Secondary instance: sending file to main → quitting")

        if send_file_to_main(ipc_socket_path, filepath) then
            mp.add_timeout(0.1, function()
                mp.commandv("quit")
            end)
        else
            msg.warn("Send failed → becoming main instance")
            create_ipc_server(ipc_socket_path)
            is_main_instance = true
        end
    end
end)
