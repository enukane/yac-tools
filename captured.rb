require "socket"
require "json"
require "thread"
require "open3"
require_relative "captured_unix_socket"

class Captured
  DEFAULT_CAP_PATH="/cap"
  DEFAULT_IFNAME="wlan0"

  CMD_GET_STATUS="get_status"
  CMD_START_CAPTURE="start_capture"
  CMD_STOP_CAPTURE="stop_capture"

  STATE_INIT="init"
  STATE_RUNNING="running"
  STATE_STOP="stop"

  CHAN = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
34, 36, 38, 40, 42, 44, 46, 48,
52, 56, 60, 64,
100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 
184, 188, 192, 196]

  def initialize ifname=DEFAULT_IFNAME, cap_path=DEFAULT_CAP_PATH
    @cap_path = cap_path || DEFAULT_CAP_PATH
    @ifname = ifname || DEFAULT_IFNAME

    check_requirements()
    init_status()

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
    @file_size = 0
    @duration = 0
    @current_channel = 0
    @channel_walk = 0
    @frame_count = 0
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
      "file_size"       => @file_size,
      "duration"        => @duration,
      "current_channel" => @current_channel,
      "channel_walk"    => @channel_walk,
      "frame_count"     => @frame_count,
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
    @th_capture = nil
    @th_tshark = nil
    @file_name = generate_new_filename()
    @current_channel = 1

    @th_capture = Thread.new do
      # these tshark/if handling should be exported away
      file_path = "#{@cap_path}/#{@file_name}"
      system("ip link set wlan0 down")
      system("iw wlan0 set monitor fcsfail otherbss control")
      system("ip link set wlan0 up")
      system("iw wlan0 set channel #{@current_channel}")
      @start_time = Time.now.to_i

      begin
      stdin, stdout, stderr, @th_tshark = *Open3.popen3(
        "tshark -i #{@ifname} -F pcapng -w #{file_path}")
      rescue => e
        p e
      end

      while @th_tshark.alive?
        sleep 1
        @duration = Time.now.to_i - @start_time
        @file_size = File.size?(file_path) || 0

        # do something that requires to run in every channel

        @current_channel = move_channel(@current_channel)
        @channel_walk += 1
        p "channel move to #{@current_channel} (dur=#{@duration}, size=#{@file_size} walk=#{@channel_walk})"
      end
    end
  end

  def do_stop_capture
    if @th_tshark == nil
      p "thread has not yet started?"
      return
    end

    p "killing pid #{@th_tshark.pid}"
    Process.kill("INT", @th_tshark.pid)
    sleep 2
    p "killing capture thread #{@th_capture}"
    @th_capture.kill
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
