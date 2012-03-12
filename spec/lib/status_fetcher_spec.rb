require 'spec_helper'

shared_examples_for "all build history fetches" do
  it "should not create a new status entry if the status has not changed since the previous fetch" do
    status_count = @project.statuses.count
    fetch_build_history_with_xml_response(@response_xml)
    @project.statuses.count.should == status_count
  end
end

shared_examples_for "status for a valid build history xml response" do
  it_should_behave_like "all build history fetches"

  it "should be online" do
    @project.status.should be_online
  end

  it "should return the link to the checkin" do
    link_elements = @response_doc.xpath("/rss/channel/item/link")
    link_elements.size.should == 1
    @project.status.url.should == link_elements.first.content
  end

  it "should return the published date of the checkin" do
    date_elements = @response_doc.xpath("/rss/channel/item/pubDate")
    date_elements.size.should == 1
    @project.status.published_at.should == Time.parse(date_elements.first.content)
  end
end

describe StatusFetcher do
  class FakeUrlRetriever
    def initialize(xml_or_exception)
      if xml_or_exception.is_a? Exception
        @exception = xml_or_exception
      else
        @xml = xml_or_exception
      end
    end

    def retrieve_content_at(*args)
      raise @exception if @exception
      @xml
    end
  end

  before(:each) do
    @project = projects(:socialitis)
  end

  describe "#fetch_build_history" do
    describe "with pubDate set with epoch" do
      before(:all) do
        @response_doc = Nokogiri::XML(@response_xml = CCRssExample.new("never_green.rss").read)
      end

      let!(:old_status_count) { @project.statuses.count }
      before(:each) do
        Timecop.freeze(Time.now)
        fetch_build_history_with_xml_response(@response_xml)
      end

      after(:each) do
        Timecop.return
      end

      it "should return current time" do
        @project.statuses.count.should == old_status_count + 1
        @project.status.published_at.to_i.should == Clock.now.to_i
      end
    end

    describe "with reported success" do
      before(:all) do
        @response_doc = Nokogiri::XML(@response_xml = CCRssExample.new("success.rss").read)
      end

      before(:each) do
        fetch_build_history_with_xml_response(@response_xml)
      end

      it_should_behave_like "status for a valid build history xml response"

      it "should report success" do
        @project.status.should be_success
        @project.status.error.should be_nil
      end
    end

    describe "with reported failure" do
      before(:all) do
        @response_doc = Nokogiri::XML(@response_xml = CCRssExample.new("failure.rss").read)
      end

      before(:each) do
        fetch_build_history_with_xml_response(@response_xml)
      end

      it_should_behave_like "status for a valid build history xml response"

      it "should report failure" do
        @project.status.should_not be_success
      end
    end

    describe "with invalid xml" do
      before(:all) do
        @response_doc = Nokogiri::XML(@response_xml = "<foo><bar>baz</bar></foo>")
      end

      before(:each) do
        fetch_build_history_with_xml_response(@response_xml)
      end

      it_should_behave_like "all build history fetches"

      it "should not be online" do
        @project.status.should_not be_online
      end
    end

    describe "with exception while parsing xml" do
      before do
        fetch_build_history_with_xml_response(Exception.new)
      end

      it "should return error" do
        @project.status.error.should match(/#{@project.name}.*Exception/)
      end
    end
  end

  describe "#fetch_building_status" do
    context "with a valid response that the project is building" do
      before(:each) do
        @response_xml = BuildingStatusExample.new("socialitis_building.xml").read
        fetch_building_status_with_xml_response(@response_xml)
      end

      it "should set the building flag on the project to true" do
        @project.should be_building
      end
    end

    context "with a project name different than CC project name" do
      before(:each) do
        @response_xml = BuildingStatusExample.new("socialitis_building.xml").read
        @project.name = "Socialitis with different name than CC project name"
        fetch_building_status_with_xml_response(@response_xml)
      end

      it "should set the building flag on the project to true" do
        @project.should be_building
      end
    end

    context "with a RSS url with different capitalization than CC project name" do
      before(:each) do
        @response_xml = BuildingStatusExample.new("socialitis_building.xml").read.downcase
        @project.feed_url = @project.feed_url.upcase
        fetch_building_status_with_xml_response(@response_xml)
      end

      it "should set the building flag on the project to true" do
        @project.should be_building
      end
    end

    context "with a valid response that the project is not building" do
      before(:each) do
        @response_xml = BuildingStatusExample.new("socialitis_not_building.xml").read
        fetch_building_status_with_xml_response(@response_xml)
      end

      it "should set the building flag on the project to false" do
        @project.should_not be_building
      end
    end

    context "with an invalid response" do
      before(:each) do
        @response_xml = "<foo><bar>baz</bar></foo>"
        fetch_building_status_with_xml_response(@response_xml)
      end

      it "should set the building flag on the project to false" do
        @project.should_not be_building
      end
    end
  end

  describe "#fetch_all" do
    context "with exception while parsing all xml" do
      before(:each) do
        retriever = mock("mock retriever")
        retriever.should_receive(:retrieve_content_at).any_number_of_times.and_raise(Exception.new('bad error'))

        @fetcher = StatusFetcher.new(retriever)
      end

      it "should fetch build history and building status for all projects needing build" do
        project_count = Project.count
        project_count.should > 1
        Project.all.each {|project| project.needs_poll?.should be_true }
        update_later = Project.first
        update_later.update_attribute(:next_poll_at, 5.minutes.from_now)  # make 1 project not ready to poll

        @fetcher.should_receive(:retrieve_status_for).exactly(project_count - 1).times.and_return(ProjectStatus.new(:success => true))
        @fetcher.should_receive(:retrieve_building_status_for).exactly(project_count - 1).times.and_return(BuildingStatus.new(false))
        @fetcher.should_not_receive(:retrieve_status_for).with(update_later)

        @fetcher.fetch_all

        Project.last.next_poll_at.should > Time.now
      end

    end
  end

  private

  def fetch_build_history_with_xml_response(xml)
    fetcher_with_mocked_url_retriever(@project.feed_url, xml).retrieve_status_for(@project)
    status = Delayed::Worker.new.work_off(1)
    @project.reload
  end

  def fetch_building_status_with_xml_response(xml)
    fetcher_with_mocked_url_retriever(@project.build_status_url, xml).retrieve_building_status_for(@project)
    status = Delayed::Worker.new.work_off(1)
    @project.reload
  end

  def fetcher_with_mocked_url_retriever(url, xml)
    StatusFetcher.new(FakeUrlRetriever.new(xml))
  end
end
