# usb.rb - utility methods for libusb binding for Ruby.
#
# Copyright (C) 2007 Tanaka Akira
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require 'usb.so'

module USB
  def USB.busses
    result = []
    bus = USB.first_bus
    while bus
      result << bus
      bus = bus.next
    end
    result.sort_by {|b| b.dirname }
  end

  def USB.devices() USB.busses.map {|b| b.devices }.flatten end
  def USB.config_descriptors() USB.devices.map {|d| d.config_descriptors }.flatten end
  def USB.interfaces() USB.config_descriptors.map {|d| d.interfaces }.flatten end
  def USB.interface_descriptors() USB.interfaces.map {|d| d.altsettings }.flatten end

  def USB.find_bus(n)
    bus = USB.first_bus
    while bus
      return bus if n == bus.dirname.to_i
      bus = bus.next
    end
    return nil
  end

  class Bus
    def inspect
      if self.revoked?
        "\#<#{self.class} revoked>"
      else
        "\#<#{self.class} #{self.dirname}>"
      end
    end

    def devices
      result = []
      device = self.first_device
      while device
        result << device
        device = device.next
      end
      result.sort_by {|d| d.filename }
    end

    def config_descriptors() self.devices.map {|d| d.config_descriptors }.flatten end
    def interfaces() self.config_descriptors.map {|d| d.interfaces }.flatten end
    def interface_descriptors() self.interfaces.map {|d| d.altsettings }.flatten end

    def find_device(n)
      device = self.first_device
      while device
        return device if n == device.filename.to_i
        device = device.next
      end
      return nil
    end
  end

  def USB.devclass_string(n)
    # http://www.usb.org/developers/defined_class
    case n
    when USB::USB_CLASS_PER_INTERFACE then return 'ClassPerInterface'
    when USB::USB_CLASS_AUDIO then return 'Audio'
    when USB::USB_CLASS_COMM then return 'Comm'
    when USB::USB_CLASS_HID then return 'HID'
    when 0x05 then return 'Physical'
    when USB::USB_CLASS_PTP then return 'Image'
    when USB::USB_CLASS_PRINTER then return 'Printer'
    when USB::USB_CLASS_MASS_STORAGE then return 'MassStorage'
    when USB::USB_CLASS_HUB then return 'Hub'
    when USB::USB_CLASS_DATA then return 'CDC-Data'
    when 0x0b then return 'SmartCard'
    when 0x0d then return 'ContentSecurity'
    when 0x0e then return 'Video'
    when 0xdc then return 'DiagnosticDevice'
    when 0xe0 then return 'WirelessController'
    when 0xef then return 'Miscellaneous'
    when 0xfe then return 'ApplicationSpecific'
    when USB::USB_CLASS_VENDOR_SPEC then return 'VendorSpecific'
    end
    nil
  end

  def USB.subclass_string(devclass, subclass)
    case devclass
    when USB::USB_CLASS_PER_INTERFACE
      case subclass
      when 0 then return ""
      end
    when USB::USB_CLASS_MASS_STORAGE
      case subclass
      when 0x01 then return "RBC"
      when 0x02 then return "ATAPI"
      when 0x03 then return "QIC-157"
      when 0x04 then return "UFI"
      when 0x05 then return "SFF-8070i"
      when 0x06 then return "SCSI"
      end
    when USB::USB_CLASS_HUB
      case subclass
      when 0 then return ""
      end
    end
    nil
  end

  def USB.devsubclass_string(c, s)
    result = USB.devclass_string(c)
    if result
      subclass = USB.subclass_string(c, s)
      if subclass
        result << "/" << subclass if subclass != ''
      else
        result << "/" << "Unknown(#{s})"
      end
    else
      result = "Unknown(#{c}/#{s})"
    end
    result
  end

  class Device
    def inspect
      if self.revoked?
        "\#<#{self.class} revoked>"
      else
        vendor_id = self.descriptor_idVendor
        product_id = self.descriptor_idProduct
        prod = [self.manufacturer, self.product, self.serial_number].compact.join(" ")
        if self.descriptor_bDeviceClass == USB::USB_CLASS_PER_INTERFACE
          devclass = self.interface_descriptors.map {|i|
            USB.devsubclass_string(i.bInterfaceClass, i.bInterfaceSubClass)
          }.join(", ")
        else
          devclass = USB.devsubclass_string(self.descriptor_bDeviceClass, self.descriptor_bDeviceSubClass)
        end

        "\#<#{self.class} #{self.bus.dirname}/#{self.filename} #{"%04x:%04x" % [vendor_id, product_id]} #{prod} (#{devclass})>"
      end
    end

    def manufacturer
      return @manufacturer if defined? @manufacturer
      @manufacturer = self.open {|h| h.get_string_simple(self.descriptor_iManufacturer) }
    end

    def product
      return @product if defined? @product
      @product = self.open {|h| h.get_string_simple(self.descriptor_iProduct) }
    end

    def serial_number
      return @serial_number if defined? @serial_number
      @serial_number = self.open {|h| h.get_string_simple(self.descriptor_iSerialNumber) }
    end

    def open
      h = self.usb_open
      if block_given?
        begin
          r = yield h
        ensure
          h.usb_close
        end
      else
        h
      end
    end

    def interfaces() self.config_descriptors.map {|d| d.interfaces }.flatten end
    def interface_descriptors() self.interfaces.map {|d| d.altsettings }.flatten end
  end

  class ConfigDescriptor
    def inspect
      if self.revoked?
        "\#<#{self.class} revoked>"
      else
        "\#<#{self.class}>"
      end
    end

    def interface_descriptors() self.interfaces.map {|d| d.altsettings }.flatten end

    def bus() self.device.bus end
  end

  class Interface
    def inspect
      if self.revoked?
        "\#<#{self.class} revoked>"
      else
        "\#<#{self.class}>"
      end
    end

    def bus() self.config_descriptor.device.bus end
    def device() self.config_descriptor.device end
  end

  class InterfaceDescriptor
    def inspect
      if self.revoked?
        "\#<#{self.class} revoked>"
      else
        devclass = USB.devsubclass_string(self.bInterfaceClass, self.bInterfaceSubClass)
        "\#<#{self.class} #{devclass}>"
      end
    end

    def bus() self.interface.config_descriptor.device.bus end
    def device() self.interface.config_descriptor.device end
    def config_descriptor() self.interface.config_descriptor end
  end

  class EndpointDescriptor
    def bus() self.interface_descriptor.interface.config_descriptor.device.bus end
    def device() self.interface_descriptor.interface.config_descriptor.device end
    def config_descriptor() self.interface_descriptor.interface.config_descriptor end
    def interface() self.interface_descriptor.interface end
  end

  class DevHandle
    def get_string_simple(index)
      result = "\0" * 256
      self.usb_get_string_simple(index, result)
      result.delete!("\0")
      result
    end
  end
end
