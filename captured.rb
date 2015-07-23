=begin

socket @ /var/run/captured.sock
pid @ /var/run/captured.pid

# input json

```
{
  "command": (get_status|start_capture|stop_capture)
}
```


# output json

```
for get_status
{
  "state": (init|stop|runing),
  "file_name": string(file name),
  "duration": int(sec),
  "current_channel": int(channel num),
  "channel_walk": int(coutner),
  "frame_count": int (counter), #TBD
}
```

=end

require "socket"
require "json"

class Captured
  STATE_INIT="init"
  STATE_RUNNNING="running"
  STATE_STOP="stop"

  def initialize
    check_requirements()
    init_status()

    @th_capture = nil
  end

  def run
    # start various connection
    @unix_sock = CapturedUnixSocket.new(Proc.new {|msg|
      recv_handler(msg)
    })
    @unix_sock.start

    loop do
    end
  end

  def check_requirements
    # root privilege
    # tshark exists?
  end

  def init_status
  end

  def recv_handler msg
    return json
  end
end
