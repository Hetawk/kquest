class Question < ApplicationRecord
  belongs_to :activity

  validates :question_type, inclusion: { in: %w[single_choice multiple_select] }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :points, numericality: { only_integer: true, in: 1..1000 }
  validates :speed_bonus_points, numericality: { only_integer: true, in: 0..100_000 }
  validates :time_limit_seconds, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 5,
    less_than_or_equal_to: Questions::Types::SingleChoice::MAX_TIME_LIMIT_SECONDS
  }
  validate :definition_is_valid
  validate :published_activity_is_immutable, if: -> { activity&.persisted? }

  private

  def definition_is_valid
    definition_errors = case question_type
    when "single_choice"
      Questions::Types::SingleChoice.definition_errors(
        prompt: prompt,
        options: options,
        correct_option_id: correct_option_id,
        points: points,
        speed_bonus_points: speed_bonus_points,
        time_limit_seconds: time_limit_seconds
      )
    when "multiple_select"
      Questions::Types::MultipleSelect.definition_errors(
        prompt: prompt,
        options: options,
        correct_option_ids: correct_option_ids || [],
        points: points,
        speed_bonus_points: speed_bonus_points,
        time_limit_seconds: time_limit_seconds
      )
    else
      {}
    end

    definition_errors.each do |attribute, message|
      errors.add(attribute, message)
    end
  end

  def published_activity_is_immutable
    return unless activity.status_in_database == "published"

    errors.add(:base, "Questions on published activities cannot be edited.")
  end
end
