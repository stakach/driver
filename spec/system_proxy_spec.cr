require "./helper"

describe EngineDriver::Proxy::System do
  Spec.before_each do
    storage = EngineDriver::Storage.new("sys-1234", "system")
    storage.delete "Display\x021"
    storage.delete "Display\x022"
    storage.delete "Display\x023"
    storage.delete "Switcher\x021"
  end

  Spec.after_each do
    storage = EngineDriver::Storage.new("sys-1234", "system")
    storage.delete "Display\x021"
    storage.delete "Display\x022"
    storage.delete "Display\x023"
    storage.delete "Switcher\x021"
  end

  it "indicate if a module / driver exists in a system" do
    cs = EngineDriver::DriverModel::ControlSystem.from_json(%(
        {
          "id": "sys-1234",
          "name": "Tesing System",
          "email": "name@email.com",
          "capacity": 20,
          "features": "in-house-pc projector",
          "bookable": true
        }
    ))

    system = EngineDriver::Proxy::System.new cs

    system.id.should eq("sys-1234")
    system.name.should eq("Tesing System")
    system.email.should eq("name@email.com")
    system.capacity.should eq(20)
    system.features.should eq("in-house-pc projector")
    system.bookable.should eq(true)

    system.exists?(:Display_1).should eq(false)

    # Create some virtual systems
    storage = EngineDriver::Storage.new(cs.id, "system")
    storage["Display\x021"] = "mod-1234"
    storage["Display\x022"] = "mod-5678"
    storage["Display\x023"] = "mod-9000"
    storage["Switcher\x021"] = "mod-9999"

    system.exists?(:Display_1).should eq(true)
    system.exists?("Display_2").should eq(true)
    system.exists?(:Display, 3).should eq(true)
    system.exists?("Switcher", "1").should eq(true)

    system.modules.should eq(["Display", "Switcher"])
    system.count("Display").should eq(3)
    system.count(:Switcher).should eq(1)
  end
end