# frozen_string_literal: true

# app/helpers/due_date_helper.rb

# This module contains helper methods related to due dates.
module DueDateHelper
  # Sorts a list of due dates by their due_at attribute.
  def self.deadline_sort(due_dates)
    # Override the comparator operator to sort due dates by due_at
    due_dates.sort { |m1, m2| m1.due_at.to_i <=> m2.due_at.to_i }
  end

  # Retrieves the default permission for a specific deadline type and permission type.
  def self.default_permission(deadline_type, permission_type)
    DeadlineRight::DEFAULT_PERMISSION[deadline_type][permission_type]
  end

  # Calculates the assignment round for a response within an assignment.
  def self.calculate_assignment_round(assignment_id, response)
    return 0 unless ResponseMap.find(response.map_id).type == 'ReviewResponseMap'

    due_dates = DueDate.where(parent_id: assignment_id)
    sorted_deadlines = deadline_sort(due_dates)
    determine_assignment_round(response, sorted_deadlines)
  end

  # Determines the assignment round for a response based on due dates.
  def self.determine_assignment_round(response, sorted_due_dates)
    round = 1
    sorted_due_dates.each do |due_date|
      break if response.created_at < due_date.due_at

      round += 1 if due_date.deadline_type_id == 2
    end
    round
  end

  # Finds the current due date that is after the current time.
  def self.find_current_due_date(due_dates)
    due_dates.find { |due_date| due_date.due_at > Time.now }
  end

  # Checks if teammate reviews are allowed for a student's assignment.
  def self.teammate_review_allowed?(student)
    due_date = find_current_due_date(student.assignment.due_dates)
    student.assignment.find_current_stage == 'Finished' ||
      (due_date && [2, 3].include?(due_date.teammate_review_allowed_id))
  end

  # Copies due dates from an old assignment to a new assignment.
  def self.copy(old_assignment_id, new_assignment_id)
    duedates = DueDate.where(parent_id: old_assignment_id)

    ActiveRecord::Base.transaction do
      duedates.each do |orig_due_date|
        duplicate_due_date(orig_due_date, new_assignment_id)
      end
    end
  end

  # Duplicates a due date for a new assignment.
  def self.duplicate_due_date(orig_due_date, new_assignment_id)
    new_due_date = orig_due_date.dup
    new_due_date.parent_id = new_assignment_id
    new_due_date.save
  end

  # Retrieves the next due date for an assignment, considering staggered deadlines.
  def self.get_next_due_date(assignment_id, topic_id = nil)
    if Assignment.find(assignment_id).staggered_deadline?
      find_next_topic_due_date(assignment_id, topic_id)
    else
      AssignmentDueDate.find_by(['parent_id = ? && due_at >= ?', assignment_id, Time.zone.now])
    end
  end

  # Finds the next due date for a specific topic within an assignment or the corresponding assignment due date if no topic due date is available.
  def self.find_next_topic_due_date(assignment_id, topic_id)
    next_due_date = TopicDueDate.find_by(['parent_id = ? and due_at >= ?', topic_id, Time.zone.now])
    # if certion TopicDueDate is not exist, we should query next corresponding AssignmentDueDate.
    # eg. Time.now is 08/28/2016
    # One topic uses following deadlines:
    # TopicDueDate      08/01/2016
    # TopicDueDate      08/02/2016
    # TopicDueDate      08/03/2016
    # AssignmentDueDate 09/04/2016
    # In this case, we cannot find due_at later than Time.now in TopicDueDate.
    # So we should find next corresponding AssignmentDueDate, starting with the 4th one, not the 1st one!
    if next_due_date.nil?
      topic_due_date_size = TopicDueDate.where(parent_id: topic_id).size
      following_assignment_due_dates = AssignmentDueDate.where(parent_id: assignment_id)[topic_due_date_size..-1]

      if following_assignment_due_dates
        next_due_date = following_assignment_due_dates.find { |due_date| due_date.due_at >= Time.zone.now }
      end
    end
    next_due_date
  end
end
