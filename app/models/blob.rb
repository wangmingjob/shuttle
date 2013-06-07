# Copyright 2013 Square Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

# Represents a Git blob found in a Project and imported. A Blob record is
# created to indicate that this blob has already been scanned for strings,
# optimizing future imports.
#
# Associations
# ============
#
# |           |                                                      |
# |:----------|:-----------------------------------------------------|
# | `project` | The {Project} whose repository this blob belongs to. |
#
# Fields
# ======
#
# |       |                                  |
# |:------|:---------------------------------|
# | `sha` | The Git identifier for the blob. |
#
# Metadata
# ========
#
# |             |                                                                                      |
# |:------------|:-------------------------------------------------------------------------------------|
# | `importers` | An array of {Importer::Base} subclass names that have already operated on this blob. |

class Blob < ActiveRecord::Base
  self.primary_keys = :project_id, :sha_raw

  belongs_to :project, inverse_of: :blobs

  include HasMetadataColumn
  has_metadata_column(
      importers: {type: Array, default: []}
  )

  extend GitObjectField
  git_object_field :sha,
                   git_type:        :blob,
                   repo:            ->(t) { t.project.try(:repo) },
                   repo_must_exist: true,
                   scope:           :with_sha

  validates :project,
            presence: true
  validates :sha,
            presence: true

  attr_accessible :sha, as: :system

  # Searches the blob for translatable strings, creates or updates Translations,
  # and associates them with this Blob. Imported strings are approved by
  # default. If the base locale is provided (or no locale), pending Translations
  # for the Project's other locales are also created (and filled with 100%
  # matches if possible).
  #
  # @param [String] path The path to this blob under the commit currently being
  #   imported.
  # @param [Hash] options Additional options.
  # @option options [Locale, nil] locale The locale to scan for strings in (by
  #   default it's the Project's base locale).
  # @option options [Commit, nil] commit If given, new Keys will be added to
  #   this Commit's `keys` association.

  def import_strings(path, options={})
    imps = Importer::Base.implementations.reject { |imp| project.skip_imports.include?(imp.to_s) }
    imps.each do |importer|
      importer = importer.new(self, path, options[:commit])
      if importer.skip?(options[:locale])
        #Importer::SKIP_LOG.info "commit=#{options[:commit].try(:revision)} blob=#{sha} path=#{path} importer=#{importer.class} #skip? returned false for #{options[:locale].inspect}"
        next
      end
      options[:locale] ? importer.import_locale(options[:locale]) : importer.import
    end
  end

  # @return [Git::Object::Blob] The Git blob this Blob represents.

  def blob
    project.repo.object(sha)
  end
end