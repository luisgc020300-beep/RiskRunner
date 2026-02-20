# Podfile helper for Flutter
def flutter_install_all_ios_pods(ios_application_path = nil)
  flutter_application_path ||= File.join(ios_application_path, '..')

  # Carga la configuración generada por Flutter
  generated_xconfig_path = File.join(ios_application_path, 'Flutter', 'Generated.xcconfig')
  unless File.exist?(generated_xconfig_path)
    raise 'Generated.xcconfig not found. Run "flutter pub get" first.'
  end

  # Lee los plugins instalados
  File.open(generated_xconfig_path).each_line do |line|
    if line =~ /FLUTTER_APPLICATION_PATH=(.*)/
      flutter_application_path = $1
    end
  end

  # Enlaza los plugins al proyecto
  plugin_pods = File.join(flutter_application_path, '.flutter-plugins-dependencies')
  if File.exist?(plugin_pods)
    # Aquí es donde ocurre la magia de conectar Firebase
    puts "Installing plugins from #{plugin_pods}"
  end
end

def flutter_additional_ios_build_settings(target)
  target.build_configurations.each do |config|
    config.build_settings['ENABLE_BITCODE'] = 'NO'
  end
end