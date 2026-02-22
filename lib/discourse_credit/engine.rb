# frozen_string_literal: true

module ::DiscourseCredit
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscourseCredit
  end
end
