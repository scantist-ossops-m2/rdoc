require 'rdoc/code_object'

##
# Abstract class representing either a method or an attribute.

class RDoc::MethodAttr < RDoc::CodeObject

  include Comparable

  ##
  # Name of this method/attribute.

  attr_accessor :name

  ##
  # public, protected, private

  attr_accessor :visibility

  ##
  # Is this a singleton method/attribute?

  attr_accessor :singleton

  ##
  # Source file token stream

  attr_reader :text

  ##
  # Array of other names for this method/attribute

  attr_reader :aliases

  ##
  # The method/attribute we're aliasing

  attr_accessor :is_alias_for

  #--
  # The attributes below are for AnyMethod only.
  # They are left here for the time being to
  # allow ri to operate.
  # TODO modify ri to avoid calling these on attributes.
  #++

  ##
  # Parameters yielded by the called block

  attr_reader :block_params

  ##
  # Parameters for this method

  attr_accessor :params

  ##
  # Different ways to call this method

  attr_accessor :call_seq

  ##
  # The call_seq or the param_seq with method name, if there is no call_seq.

  attr_reader :arglists

  ##
  # Pretty parameter list for this method

  attr_reader :param_seq


  def initialize(text, name)
    super()

    @text = text
    @name = name

    @aliases      = []
    @is_alias_for = nil
    @parent_name  = nil
    @singleton    = nil
    @visibility   = :public
    @see = false

    @arglists     = nil
    @block_params = nil
    @call_seq     = nil
    @full_name    = nil
    @param_seq    = nil
    @params       = nil
  end

  ##
  # Order by #singleton then #name

  def <=>(other)
    [@singleton ? 0 : 1, name] <=> [other.singleton ? 0 : 1, other.name]
  end

  ##
  # A method/attribute is documented if any of the following is true:
  # - it was marked with :nodoc:;
  # - it has a comment;
  # - it is an alias for a documented method;
  # - it has a +#see+ method that is documented.

  def documented?
    super || (is_alias_for && is_alias_for.documented?) || (see && see.documented?)
  end

  ##
  # A method/attribute to look at,
  # in particular if this method/attribute has no documentation.
  #
  # It can be a method/attribute of the superclass or of an included module,
  # including the Kernel module, which is always appended to the included
  # modules.
  #
  # Returns +nil+ if there is no such method/attribute.
  # The +#is_alias_for+ method/attribute, if any, is not included.
  #
  # Templates may generate a "see also ..." if this method/attribute
  # has documentation, and "see ..." if it does not.

  def see
    @see = find_see if @see == false
    @see
  end

  def find_see # :nodoc:
    return nil if singleton || is_alias_for
    # look for the method
    other = find_method_or_attribute name
    return other if other
    # if it is a setter, look for a getter
    return nil unless name =~ /[a-z_]=$/i   # avoid == or ===
    return find_method_or_attribute name[0..-2]
  end

  def find_method_or_attribute(name) # :nodoc:
    searched = parent.ancestors
    kernel = RDoc::TopLevel.all_modules_hash['Kernel']
    searched << kernel if kernel && parent != kernel && !searched.include?(kernel)
    searched.each do |ancestor|
      next if ancestor.is_a?(String)
      other = ancestor.find_method_named('#' << name) || ancestor.find_attribute_named(name)
      return other if other
    end
    nil
  end

  ##
  # Abstract method. Contexts in their building phase call this
  # to register a new alias for this known method/attribute.
  #
  # - creates a new AnyMethod/Attribute +newa+ named an_alias.new_name;
  # - adds +self+ as +newa.is_alias_for+;
  # - adds +newa+ to #aliases
  # - adds +newa+ to the methods/attributes of +context+.

  def add_alias(an_alias, context)
    raise NotImplementedError
  end

  ##
  # HTML fragment reference for this method

  def aref
    type = singleton ? 'c' : 'i'
    # % characters are not allowed in html names => dash instead
    "#{aref_prefix}-#{type}-#{html_name}"
  end

  ##
  # Prefix for +aref+, defined by subclasses.

  def aref_prefix
    raise NotImplementedError
  end

  ##
  # Attempts to sanitize the content passed by the ruby parser:
  # remove outer parentheses, etc.

  def block_params=(value)

    # thinks like 'yield.to_s' or 'assert yield, msg'
    return @block_params = '' if value =~ /^[\.,]/

    # remove trailing 'if/unless ...'
    if value =~ /^(if|unless)\s/
      return @block_params = ''
    end
    value = $1.strip if value =~ /^(.+)\s(if|unless)\s/

    # outer parentheses
    value = $1 if value =~ /^\s*\((.*)\)\s*$/
    value = value.strip

    # proc/lambda
    return @block_params = $1 if value =~ /^(proc|lambda)(\s*\{|\sdo)/

    # surrounding +...+ or [...]
    value = $1.strip if value =~ /^\+(.*)\+$/
    value = $1.strip if value =~ /^\[(.*)\]$/

    return @block_params = '' if value.empty?

    # global variable
    return @block_params = 'str' if value =~ /^\$[&0-9]$/

    # wipe out array/hash indices
    value.gsub!(/(\w)\[[^\[]+\]/, '\1')

    # remove @ from class/instance variables
    value.gsub!(/@@?([a-z0-9_]+)/, '\1')

    # method calls => method name
    value.gsub!(/([A-Z:a-z0-9_]+)\.([a-z0-9_]+)(\s*\(\s*[a-z0-9_.,\s]*\s*\)\s*)?/) do |m|
      case $2
      when 'to_s';      $1
      when 'const_get'; 'const'
      when 'new';       $1.split('::').last.  # ClassName => class_name
                          gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
                          gsub(/([a-z\d])([A-Z])/,'\1_\2').
                          downcase
      else;             $2
      end
    end

    # class prefixes
    value.gsub!(/[A-Za-z0-9_:]+::/, '')

    # simple expressions
    value = $1 if value =~ /^([a-z0-9_]+)\s*[-*+\/]/

    @block_params = value.strip
  end

  ##
  # HTML id-friendly method/attribute name

  def html_name
    CGI.escape(@name.gsub('-', '-2D')).gsub('%','-').sub(/^-/, '')
  end

  ##
  # Full method/attribute name including namespace

  def full_name
    @full_name || "#{parent_name}#{pretty_name}"
  end

  ##
  # '::' for a class method/attribute, '#' for an instance method.

  def name_prefix
    singleton ? '::' : '#'
  end

  ##
  # Method/attribute name with class/instance indicator

  def pretty_name
    "#{name_prefix}#{@name}"
  end

  ##
  # Type of method/attribute (class or instance)

  def type
    singleton ? 'class' : 'instance'
  end

  ##
  # Path to this method

  def path
    "#{@parent.path}##{aref}"
  end

  ##
  # Name of our parent with special handling for un-marshaled methods

  def parent_name
    @parent_name || super
  end

  def pretty_print q # :nodoc:
    alias_for = @is_alias_for ? "alias for #{@is_alias_for.name}" : nil

    q.group 2, "[#{self.class.name} #{full_name} #{visibility}", "]" do
      if alias_for then
        q.breakable
        q.text alias_for
      end

      if text then
        q.breakable
        q.text "text:"
        q.breakable
        q.pp @text
      end

      unless comment.empty? then
        q.breakable
        q.text "comment:"
        q.breakable
        q.pp @comment
      end
    end
  end

  def inspect # :nodoc:
    alias_for = @is_alias_for ? " (alias for #{@is_alias_for.name})" : nil
    "#<%s:0x%x %s (%s)%s>" % [
      self.class, object_id,
      full_name,
      visibility,
      alias_for,
    ]
  end

  def to_s # :nodoc:
    if @is_alias_for
      "#{self.class.name}: #{full_name} -> #{is_alias_for}"
    else
      "#{self.class.name}: #{full_name}"
    end
  end

end
