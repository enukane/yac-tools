require "socket"
require "json"
require "thread"
require "open3"
require_relative "captured_unix_socket"
require_relative "wlan"

class Captured
  DEFAULT_CAP_PATH="/cap"
  DEFAULT_IFNAME="wlan0"

  CMD_GET_STATUS="get_status"
  CMD_START_CAPTURE="start_capture"
  CMD_STOP_CAPTURE="stop_capture"

  STATE_INIT="init"
  STATE_RUNNING="running"
  STATE_STOP="stop"

  def initialize ifname=DEFAULT_IFNAME, cap_path=DEFAULT_CAP_PATH
    @cap_path = cap_path || DEFAULT_CAP_PATH
    @ifname = ifname || DEFAULT_IFNAME

    check_requirements()
    init_status()

    @wlan = Wlan.new(@ifname)

    @th_capture = nil
    @event_q = Queue.new
    @start_time = 0

    @mutex = Mutex.new
    @cv = ConditionVariable.new
  end

  def run
    # start various connection
    @unix_sock = CapturedUnixSocket.new(Proc.new {|msg|
      recv_handler(msg)
    })
    @unix_sock.start

    loop do
      @mutex.synchronize {
        @cv.wait(@mutex) if @event_q.empty?
        event = @event_q.pop
        p "received event : #{event}"
        handle_event(event)
      }
    end
  end

  def check_requirements
    # root privilege
    # tshark exists?
  end

  def init_status new_state=STATE_INIT
    @state = new_state
    @file_name = ""
  end

  def recv_handler msg
    p "received => #{msg}"
    json = JSON.parse(msg)

    resp = {}

    case json["command"]
    when CMD_GET_STATUS
      resp = recv_get_status()
    when CMD_START_CAPTURE
      resp = recv_start_capture()
    when CMD_STOP_CAPTURE
      resp = recv_stop_capture()
    else
      p "ERROR: unknown command = #{json['command']}"
      resp = {"error" => "unknown command"}
    end

    return JSON.dump(resp)
  rescue => e
    p e
  end

  def recv_get_status
    p "command get_status"
    return status_hash()
  end

  def recv_start_capture
    p "command start_capture"

    @mutex.synchronize {
      p "sync"
      @event_q.push(CMD_START_CAPTURE)
      p "signall #{@cv}"
      @cv.signal if @cv
      p "done?"
    }

    p "done queueing start capture"
    return {"status" => "start capture enqueued"}
  end

  def recv_stop_capture
    p "command stop_capture"

    @mutex.synchronize {
      @event_q.push(CMD_STOP_CAPTURE)
      @cv.signal if @cv
    }

    p "done queueing stop capture"
    return {"status" => "stop capture enqueued"}
  end

  def status_hash
    return {
      "state"           => @state,
      "file_name"       => @file_name,
      "file_size"       => @wlan.file_size,
      "duration"        => @wlan.duration,
      "current_channel" => @wlan.current_channel,
      "channel_walk"    => @wlan.channel_walk,
    }
  end

  def handle_event event
    case event
    when CMD_START_CAPTURE
      p "handler => start_capture"
      start_capture
    when CMD_STOP_CAPTURE
      p "handler => stop_capture"
      stop_capture
    else
      p "unknown event => #{event}"
    end
  rescue => e
    p "error => #{e}"
  end

  def start_capture
    if @state == STATE_RUNNING and @th_capture
      return # do nothing
    end
    init_status() # refresh

    @state = STATE_RUNNING
    do_start_capture()
    return
  end

  def stop_capture
    if @state != STATE_RUNNING
      return
    end

    do_stop_capture()
    @state = STATE_STOP
    return
  end

  def do_start_capture
    @file_name = generate_new_filename()

    @th_capture = Thread.new do
      file_path = "#{@cap_path}/#{@file_name}"
      @wlan.run_capture(file_path) # block until stopped
    end
  end

  def do_stop_capture
    @wlan.stop_capture

    p "killing capture thread #{@th_capture}"
    @th_capture.kill if @th_capture
  end

  def generate_new_filename()
    return "#{Time.now.strftime("%Y%m%d%H%m%S")}_#{@ifname}_#{$$}.pcapng"
  end

  def move_channel current
    # this is shit
    return (current + 1) % 13 + 1
  end
end

if __FILE__ == $0
  Captured.new.run
end
