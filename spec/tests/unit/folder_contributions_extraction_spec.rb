# frozen_string_literal: true

require_relative '../../helpers/spec_helper'

describe 'Unit test of Representer::FolderContributions subfolder extraction' do
  FIXTURES_PATH = File.join(File.dirname(__FILE__), '../../fixtures/json')

  def sample_appraisal_json
    File.read(File.join(FIXTURES_PATH, 'sample_appraisal.json'))
  end

  def error_appraisal_json
    File.read(File.join(FIXTURES_PATH, 'error_appraisal.json'))
  end

  describe 'extract_subfolder' do
    it 'should return root folder for empty path' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(
        sample_appraisal_json, ''
      )

      _(result).wont_be_nil
      _(result.path).must_equal ''
      _(result.line_count).must_equal 1000
    end

    it 'should return root folder for nil path' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(
        sample_appraisal_json, nil
      )

      _(result).wont_be_nil
      _(result.path).must_equal ''
    end

    it 'should extract top-level subfolder' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(
        sample_appraisal_json, 'app'
      )

      _(result).wont_be_nil
      _(result.path).must_equal 'app'
      _(result.line_count).must_equal 500
    end

    it 'should extract nested subfolder' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(
        sample_appraisal_json, 'app/domain'
      )

      _(result).wont_be_nil
      _(result.path).must_equal 'app/domain'
      _(result.line_count).must_equal 200
    end

    it 'should extract deeply nested subfolder' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(
        sample_appraisal_json, 'app/domain/entities'
      )

      _(result).wont_be_nil
      _(result.path).must_equal 'app/domain/entities'
      _(result.line_count).must_equal 100
    end

    it 'should return nil for non-existent folder' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(
        sample_appraisal_json, 'nonexistent'
      )

      _(result).must_be_nil
    end

    it 'should return nil for non-existent nested folder' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(
        sample_appraisal_json, 'app/nonexistent'
      )

      _(result).must_be_nil
    end

    it 'should handle trailing slashes' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(
        sample_appraisal_json, 'app/domain/'
      )

      _(result).wont_be_nil
      _(result.path).must_equal 'app/domain'
    end

    it 'should handle leading slashes' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(
        sample_appraisal_json, '/app/domain'
      )

      _(result).wont_be_nil
      _(result.path).must_equal 'app/domain'
    end

    it 'should return nil for error appraisal' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(
        error_appraisal_json, ''
      )

      _(result).must_be_nil
    end

    it 'should return nil for nil json' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(nil, '')

      _(result).must_be_nil
    end

    it 'should return nil for empty json' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder('', '')

      _(result).must_be_nil
    end

    it 'should return nil for invalid json' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder(
        'not valid json', ''
      )

      _(result).must_be_nil
    end
  end

  describe 'extract_subfolder_json' do
    it 'should return JSON string for valid subfolder' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder_json(
        sample_appraisal_json, 'app'
      )

      _(result).wont_be_nil
      parsed = JSON.parse(result)
      _(parsed['path']).must_equal 'app'
      _(parsed['line_count']).must_equal 500
    end

    it 'should return nil for non-existent folder' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder_json(
        sample_appraisal_json, 'nonexistent'
      )

      _(result).must_be_nil
    end

    it 'should preserve nested structure in JSON output' do
      result = CodePraise::Representer::FolderContributions.extract_subfolder_json(
        sample_appraisal_json, 'app'
      )

      _(result).wont_be_nil
      parsed = JSON.parse(result)
      _(parsed['subfolders']).wont_be_nil
      _(parsed['subfolders'].length).must_equal 2
    end
  end
end
