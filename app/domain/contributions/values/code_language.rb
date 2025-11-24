# frozen_string_literal: true

# rubocop:disable Style/Documentation
module CodePraise
  module Value
    module CodeLanguage
      WHITESPACE = '[ \t]'
      LINE_END = '$'

      # Registry for language classes
      @registry = {}

      def self.register(extension, language_class)
        @registry[extension] = language_class
      end

      def self.extension_language(file_extension)
        @registry.fetch(file_extension) { Unknown }
      end

      def self.wanted_extensions
        @registry.keys.freeze
      end

      module LanguageMethods
        attr_reader :code

        def self.included(base)
          base.extend(ClassMethods)
        end

        def setup(code)
          @code = code
        end

        def name
          self.class.lang_name
        end

        def useless?
          code.match?(self.class.const_get(:USELESS))
        end

        # Delegate to class methods
        def wanted? = self.class.wanted?
        def unwanted? = self.class.unwanted?

        module ClassMethods
          def extension(ext = nil)
            if ext
              @extension = ext
              CodeLanguage.register(ext, self)
            end
            @extension
          end

          # Single source of truth for wanted/unwanted at class level
          def wanted? = true
          def unwanted? = !wanted?
        end
      end

      class Ruby
        include LanguageMethods

        extension 'rb'

        def initialize(code) = setup(code)
        COMMENT = '[#\/]'
        USELESS = /^#{WHITESPACE}*(#{COMMENT}|#{LINE_END})/
      end

      class Python
        include LanguageMethods

        extension 'py'

        def initialize(code) = setup(code)
        COMMENT = '[#\/]'
        USELESS = /^#{WHITESPACE}*(#{COMMENT}|#{LINE_END})/
      end

      class Javascript
        include LanguageMethods

        extension 'js'

        def initialize(code) = setup(code)
        COMMENT = '//'
        USELESS = /^#{WHITESPACE}*(#{COMMENT}|#{LINE_END})/
      end

      class Html
        include LanguageMethods

        extension 'html'

        def initialize(code) = setup(code)
        USELESS = /^#{WHITESPACE}*#{LINE_END}/
      end

      class Erb
        include LanguageMethods

        extension 'erb'

        def initialize(code) = setup(code)
        USELESS = /^#{WHITESPACE}*#{LINE_END}/
      end

      class Slim
        include LanguageMethods

        extension 'slim'

        def initialize(code) = setup(code)
        USELESS = /^#{WHITESPACE}*#{LINE_END}/
      end

      class Css
        include LanguageMethods

        extension 'css'

        def initialize(code) = setup(code)
        USELESS = /^#{WHITESPACE}*#{LINE_END}/
      end

      class Markdown
        include LanguageMethods

        extension 'md'

        def initialize(code) = setup(code)
        USELESS = /^#{WHITESPACE}*#{LINE_END}/
      end

      class Unknown
        include LanguageMethods

        def initialize(code) = setup(code)
        # Override: all lines are useless
        def useless? = true
        def self.lang_name = 'not recognized'
        # Override: class is not wanted
        def self.wanted? = false
      end

      UNKNOWN_LANGUAGE = CodeLanguage::Unknown.freeze
    end
  end
end
# rubocop:enable Style/Documentation
