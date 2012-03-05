class FixtureFile
  def initialize(subdir, filename)
    @content = File.read(File.join(Rails.root, "spec", "fixtures", subdir, filename))
  end

  def read
    @content
  end

  def as_xml
    Nokogiri::XML(@content)
  end
end

class BuildingStatusExample < FixtureFile
  def initialize(filename)
    super("building_status_examples", filename)
  end
end

class CCRssExample < FixtureFile
  def initialize(filename)
    super("cc_rss_examples", filename)
  end

  def xpath_content(xpath)
    as_xml.at_xpath(xpath).content
  end
end

class HudsonAtomExample < FixtureFile
  def initialize(filename)
    super("hudson_atom_examples", filename)
  end

  def as_xml
    Nokogiri::XML.parse(read)
  end

  def first_css(selector)
    as_xml.at_css(selector)
  end
end

class TeamcityAtomExample < FixtureFile
  def initialize(filename)
    super("teamcity_atom_examples", filename)
  end
end

class TeamcityCradiatorXmlExample < FixtureFile
  def initialize(filename)
    super("teamcity_cradiator_xml_examples", filename)
  end

  def as_xml
    Nokogiri::XML.parse(read)
  end

  def first_css(selector)
    as_xml.at_css(selector)
  end
end

class TeamcityRESTExample < FixtureFile
  def initialize(filename)
    super("teamcity_rest_examples", filename)
  end

  def as_xml
    Nokogiri::XML.parse(read)
  end

  def first_css(selector)
    as_xml.at_css(selector)
  end
end

class PivotalTrackerExample < FixtureFile
  def initialize(filename)
    super("pivotal_tracker_examples", filename)
  end

  def retrieve_content_at(*args)
    read
  end

end