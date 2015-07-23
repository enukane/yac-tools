require "json"
require "socket"


class CaptureAgent
  attr_reader :state, :file_name, :file_size, :duration, :current_channel, :frame_count, :channel_walk
  SOCKPATH="/var/run/captured.sock"

  CMD_GET_STATUS="get_status"
  CMD_START_CAPTURE="start_capture"
  CMD_STOP_CAPTURE="stop_capture"

  STATE_INIT="init"
  STATE_RUNNING="running"
  STATE_STOP="stop"
  StATE_UNKNOWN="unknown"

  def initialize
    @state = STATE_INIT
    @file_name = "<None>"
    @file_size = 0
    @duration = 0
    @current_channel = 0
    @channel_walk = 0
    @frame_count = 0
  end

  def get_status
    resp = do_rpc(get_msg(CMD_GET_STATUS))
    if resp["state"] != nil
      update_state(resp)
      return true
    end

    # not responded?
    @state = STATE_UNKNOWN
    return false
  rescue
    p "failed to get_status"
    return false
  end

  def start_capture
    resp = do_rpc(get_msg(CMD_START_CAPTURE))
    resp = get_status()
    if resp["state"] == STATE_RUNNING
      update_state(resp)
      return true
    end

    # not responded or failed
    @state = STATE_UNKNOWN
    return false
  end

  def stop_capture
    resp = do_rpc(get_msg(CMD_START_CAPTURE))
    resp = get_status()
    if resp["state"] == STATE_STOP
      update_state(resp)
      return true
    end

    # not responded?
    p "ERROR: failed to stop captured?"
    return false
  end

  private
  def get_msg type=CMD_GET_STATUS
    JSON.dump(
      {"command": type}
    )
  end

  def do_rpc req_json_msg
    data = {}
    UNIXSocket.open(SOCKPATH) do |sock|
      sock.write(req_json_msg+"\n")
      data = sock.gets
    end
    return JSON.parse(data)
  rescue Errno::EPIPE => e
    p "ERROR: RPC failed"
    return {}
  rescue JSON::ParserError => e0
    p "ERROR: Received text is not JSON"
    return {}
  end

  def update_state msg
    @state = msg["state"]
    @file_name = msg["file_name"]
    @file_size = msg["file_size"]
    @duration = msg["duration"]
    @current_channel = msg["current_channel"]
    @channel_walk = msg["channel_walk"]
    @frame_count = msg["frame_count"]
  end
end
