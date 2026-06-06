# Creates a test course with teacher, 5 students, a graded discussion,
# and enables the discussion_thread_summarizer feature flag.

ROOT_ACCOUNT = Account.default

# -- Teacher --
teacher = User.where(name: "Test Teacher").first_or_initialize
teacher.workflow_state = "registered"
teacher.save!(validate: false)
unless teacher.pseudonyms.where(unique_id: "teacher@test.canvas").exists?
  teacher.pseudonyms.create!(
    unique_id:    "teacher@test.canvas",
    password:     "changeme1234",
    password_confirmation: "changeme1234",
    account:      ROOT_ACCOUNT
  )
end
puts "Teacher: teacher@test.canvas / changeme1234"

# -- Students --
5.times do |i|
  n = i + 1
  email = "student#{n}@test.canvas"
  student = User.where(name: "Student #{n}").first_or_initialize
  student.workflow_state = "registered"
  student.save!(validate: false)
  unless student.pseudonyms.where(unique_id: email).exists?
    student.pseudonyms.create!(
      unique_id:    email,
      password:     "changeme1234",
      password_confirmation: "changeme1234",
      account:      ROOT_ACCOUNT
    )
  end
  puts "Student #{n}: #{email} / changeme1234"
end

# -- Course --
course = Course.where(name: "Discussion Summarizer Test").first_or_initialize
course.account    = ROOT_ACCOUNT
course.workflow_state = "available"
course.save!
puts "Course: '#{course.name}' (id=#{course.id})"

# -- Enroll teacher --
course.enroll_teacher(teacher, enrollment_state: "active")

# -- Enroll students --
User.where("name LIKE 'Student _'").find_each do |s|
  course.enroll_student(s, enrollment_state: "active")
end

# -- Enable feature flag on account and course --
ROOT_ACCOUNT.enable_feature!(:discussion_thread_summarizer)
course.enable_feature!(:discussion_thread_summarizer)
puts "Feature flag enabled on account + course"

# -- Discussion topic --
topic = course.discussion_topics.where(title: "Summarizer Test Discussion").first_or_initialize
topic.user    = teacher
topic.message = "<p>What do you think is the most important skill for a software engineer? Share your perspective and respond to at least two classmates.</p>"
topic.save!
puts "Discussion topic: '#{topic.title}' (id=#{topic.id})"

# -- Seed a few student replies so there's something to summarize --
opinions = [
  "I think communication is the most important skill. Without it, even the best code is wasted.",
  "Problem-solving ability matters most to me. Technology changes, but thinking clearly doesn't.",
  "Adaptability — the stack you use today will be different in two years.",
  "Attention to detail. A missing semicolon or a wrong assumption can cause hours of debugging.",
  "Empathy for the user. We build software for people, so understanding them is foundational."
]

User.where("name LIKE 'Student _'").order(:name).each_with_index do |s, i|
  existing = topic.discussion_entries.where(user: s).exists?
  unless existing
    topic.discussion_entries.create!(user: s, message: "<p>#{opinions[i]}</p>")
    puts "  Reply from #{s.name}"
  end
end

puts "\nDone. Visit /courses/#{course.id}/discussion_topics/#{topic.id} to see the discussion."
