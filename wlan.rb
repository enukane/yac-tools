class Wlan
  attr_reader :duration, :current_channel, :file_size, :channel_walk
  CHAN = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
    34, 36, 38, 40, 42, 44, 46, 48,
    52, 56, 60, 64,
    100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 
    184, 188, 192, 196]
  LIMIT_IDX=CHAN.length

  def initialize ifname=DEFAULT_IFNAME
    @th_shark = nil
    @ifname = ifname || DEFAULT_IFNAME
    init_status()
    @black_list = []
  end

  def run_capture fpath
    init_device()
    init_status()
    start_time = Time.now.to_i

    stdin, stdout, stderr, @th_tshark = *Open3.popen3(
      "tshark -i #{@ifname} -F pcapng -w #{fpath}")

    while @th_tshark.alive?
      sleep 1

      # update status
      @duration = Time.now.to_i - start_time
      @file_size = File.size?(fpath) || 0

      # do something here to run before channel transition

      @current_chanenl = move_channel(@current_channel)
      @channel_walk += 1
      p "channel moved to #{@current_channel} (dur=#{@duration}, size=#{@file_size} walk=#{@channel_walk}"
    end
  rescue => e
    p e
  end

  def stop_capture
    if @th_tshark == nil
      p "tshark thread has not initiated"
      return
    end

    Process.kill("INT", @th_tshark.pid)
  end

  private
  def init_status
    @duration = 0
    @current_channel = 1
    @file_size = 0
    @channel_walk = 0
  end

  def init_device
    unless system("ip link set #{@ifname} down")
      raise "failed to turn down #{@ifname}"
    end
    unless system("iw #{@ifname} set monitor fcsfail otherbss control")
      raise "failed to set #{@ifname} to monitor mode"
    end
    unless system("ip link set #{@ifname} up")
      raise "failed to turn up #{@ifname}"
    end
    unless system("iw wlan0 set channel #{@current_channel}")
      raise "failed to set channel #{@current_channel} on #{@ifname}"
    end
  end

  def move_channel current
    next_channel = pick_channel(current)

    while !system("iw #{@ifname} set channel #{next_channel}")
      # what if we got unplugged ifname? => should we die?
      p "channel transition failed (next=#{next_channel})"
      @black_list << next_channel
      sleep 1
      next_channel = pick_channel(next_channel)
    end

    @current_channel = next_channel
  end

  def pick_channel current
    idx = CHAN.index(current)
    idx += 1
    next_channel = CHAN[idx % LIMIT_IDX]

    # we have black list
    while @black_list.include?(next_channel)
      idx += 1
      next_channel = CHAN[idx % LIMIT_IDX]
    end

    return next_channel
  end
end
