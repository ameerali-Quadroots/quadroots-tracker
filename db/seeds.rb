# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
AdminUser.create!(email: 'admin@example.com', password: 'password', password_confirmation: 'password') if Rails.env.development?
data = [
  ["Muhammad Mahin Shahzad", 5, 0, 0],
  ["Ali Awais", 3, 0, 0],
  ["Ali Mesum", 0, 0, 4],
  ["Syed Muhammad Murtaza Zaidi", 2, 0, 2],
  ["Sarim Ali", 0, 2, 0],
  ["Rafay Imdad", 2, 0, 0],
  ["Ali Raza Khan", 4, 2, 0],
  ["Hassan Shahzad", 1.5, 0, 0],
  ["Muhammad Zaki Ul Hassan", 1.5, 1, 0],
  ["Muhammad Ahmed Khan", 0, 2, 1],
  ["Sameer Gulzar", 11, 0, 0],
  ["Muhammad Zubair", 2, 1, 0],
  ["Anayat Ullah Arif", 2, 0, 0],
  ["Wajahat Ali Rana", 6.5, 0, 0],
  ["Ameer Ali", 1, 0, 3],
  ["Nida Farooq", 10, 0, 0],
  ["Muhammad Sufyan", 2.5, 1, 1],
  ["Amir Hussain", 3, 2, 0],
  ["Hamna Amir", 1.5, 0, 0],
  ["Mahrukh Shehzad", 3.5, 1, 0],
  ["Fatima Zubair", 1, 0, 0],
  ["Muhammad Areez", 0, 0, 0],
  ["Faraz Imdad", 1, 0, 3],
  ["Ahmed Salman", 0, 0, 3],
  ["Syed Owais Nayyar", 2, 0, 0],
  ["Ghufran Ali", 4, 0, 0],
  ["Qasim Mughal", 4.5, 0, 2],
  ["Mehwish Shahzad", 2, 0, 0],
  ["Minahil Nadeem", 3, 0, 0],
  ["Hussnain Tahir", 3, 0, 0],
  ["Sahil Shahzad", 4, 0, 0],
  ["Insha Aslam Khan", 3, 0, 1],
  ["Muhammad Ahmad Khalid", 0, 0, 0],
  ["Rashid", 1, 0, 0],
  ["Mahnoor Khan", 0, 0, 0],
  ["Adeel Ahmed Rashid", 2, 0, 0],
  ["Abdul Rafay", 0, 0, 0],
  ["Ahmed Haq Nawaz", 0, 0, 0],
  ["Zaftal Security Company", 0, 0, 0],
  ["Muteeb Imran", 1, 0, 1],
  ["Junaid Ali", 1, 1, 5],
  ["Holscott International", 0, 0, 0],
  ["Muhammad Muneeb Ali", 1, 0, 0],
  ["Abdul Wali Siddiqui", 3, 0, 0],
  ["Hussnain Haider", 1, 0, 0],
  ["Laique Wajid", 0, 0, 0],
  ["Shahzad Masih", 0, 0, 1],
  ["Najaf ul Qammar", 3, 1, 0],
  ["Muhammad Ukkasha", 2, 1, 0],
  ["Abraham Ghafoor", 3, 0, 0],
  ["Sania Ghafoor", 1, 1, 0],
  ["Muhammad Fatiq", 2.5, 0, 0],
  ["Kamran Ahmed", 2.5, 0, 1],
  ["Muhammad Hammad Azhar", 2, 0, 0],
  ["Muhammad Faizan", 1, 0, 1],
  ["Muhammad Arqam Imran", 0, 0, 1],
  ["Ammar Ali Shoukat", 0, 1, 1],
  ["Khizer Khalid", 1, 0, 0],
  ["Kaylee Martinez", 5.5, 0, 0],
  ["Yusra Saleem", 4, 1, 0],
  ["Masfa Tanveer", 5, 0, 0],
  ["Muhammad Haris", 3, 0, 0],
  ["Ishtiaq Ahmed", 2, 1, 0],
  ["Sohail Ashraf", 1, 0, 1],
  ["Muhammad Kumail Ali", 0, 0, 0],
  ["Musaab Amir", 0.5, 0, 0],
  ["Ayesha Mustafa", 2, 1, 0],
  ["Syed Mubashir Hussain", 1, 0, 2],
  ["Sarim Muhammad", 2, 0, 0],
  ["Sajjawal Sajjad", 0, 0, 0],
  ["Muhammad Mustajab Shahid", 0, 0, 0],
  ["Muhammad Ali Abid", 0, 0, 0],
  ["Ameer Hamza", 0, 0, 1],
  ["Maroof Mushtaq", 2, 0, 0],
  ["Rushna Amir", 1, 0, 0],
  ["Muhammad Nasir", 2, 0, 0],
  ["Muhammad Hammad Azhar", 1, 0, 0],
  ["Syed Muhammad Kazim Naqvi", 0, 0, 1],
  ["Momina Khan", 0, 0, 0],
  ["Ameer Hamza", 0, 0, 1],
  ["Junaid Alam", 0, 0, 0]
]

data.each do |full_name, casual, half_day, medical|
  user = User.find_by(name: full_name)

  if user.nil?
    puts "⚠️ User not found: #{full_name}"
    next
  end

  casual_count = casual.to_f.floor
  half_day_count = half_day.to_f.floor
  medical_count = medical.to_f.floor

  # ✅ Casual leaves
  casual_count.times do
    Leave.create!(
      user: user,
      leave_type: "casual",
      start_date: Date.today,
      end_date: Date.today,
      reason: "Casual leave (auto-imported)",
      status: "approved",
      approved_by_manager: true
    )
  end

  # ✅ Half-day leaves
  half_day_count.times do
    Leave.create!(
      user: user,
      leave_type: "half_day",
      start_date: Date.today,
      end_date: Date.today,
      reason: "Half-day leave (auto-imported)",
      status: "approved",
      approved_by_manager: true
    )
  end

  # ✅ Medical leaves
  medical_count.times do
    Leave.create!(
      user: user,
      leave_type: "medical",
      start_date: Date.today,
      end_date: Date.today,
      reason: "Medical leave (auto-imported)",
      status: "approved",
      approved_by_manager: true
    )
  end

  puts "✅ Added #{casual_count} casual, #{half_day_count} half-day, and #{medical_count} medical leaves for #{full_name}"
end

puts "🎉 Import complete!"
