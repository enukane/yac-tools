require "wiringpi"

class PiTFTButton
  PIN1 = 4
  PIN2 = 3
  PIN3 = 2
  PIN4 = 1

  PIN_MODE_INPUT=0

  def initialize
    if ENV['BUTTON_MOCK'] != nil
      dummy_init
    else
      real_init
    end

    @prev = [false, false, false, false]
  end

  def dummy_init
    # do nothing
  end

  def real_init
    @io = WiringPi::GPIO.new

    [PIN1, PIN2, PIN3, PIN4].each do |pin|
      @io.pin_mode(pin, PIN_MODE_INPUT)
      @io.pull_up_dn_control(pin, WiringPi::PUD_UP)
    end
  end

  def button_all
    return [button1, button2, button3, button4]
  end

  def button1
    read_button(PIN1)
  end

  def button2
    read_button(PIN2)
  end

  def button3
    read_button(PIN3)
  end

  def button4
    read_button(PIN4)
  end

  def button_all_edge
    buttons = button_all()
    edges = []
    0.upto(3) do |n|
      if buttons[n] == true and buttons[n] != @prev[n]
        edges[n] = true
      else
        edges[n] = false
      end
    end

    @prev = buttons
    return edges
  end

  private
  def read_button pin
    return @io.digital_read(pin) == 0
  end
end

if __FILE__ == $0
  pitftb = PiTFTButton.new
  while true
    buttons = pitftb.button_all_edge
    0.upto(3) do |n|
      bn = n + 1
      if buttons[n] == true
        print "Button #{bn} is On"
      end
    end
  end
end
