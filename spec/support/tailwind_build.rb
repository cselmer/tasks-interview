RSpec.configure do |config|
  config.before(:suite) do
    unless Rails.root.join("app/assets/builds/tailwind.css").exist?
      system("bin/rails tailwindcss:build", exception: true)
    end
  end
end
