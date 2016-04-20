#
#The MIT License (MIT)
#
#Copyright (c) 2016, Groupon, Inc.
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in
#all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#THE SOFTWARE.
#
require 'open-uri'
require 'tempfile'
require 'pipeline'

module CodeburnerUtil

  def self.github
    Octokit.configure do |c|
      if Setting.github[:api_endpoint]
        c.api_endpoint = Setting.github[:api_endpoint]
      end
    end

    Octokit::Client.new(:access_token => Setting.github[:api_access_token])
  end

  def self.severity_to_text severity
    sev_text = [ 'Unknown', 'Low', 'Medium', 'High' ]
    return sev_text[severity]
  end

  def self.strip_github_path repo_url
    uri = URI.parse(repo_url)
    return uri.path.gsub(/^\//,'').gsub(/\/$/,'').gsub('.git','')
  end

  def self.inside_github_archive repo_url, ref
    dir = Dir.mktmpdir
    filename = Dir::Tmpname.make_tmpname(['codeburner', '.tar.gz'], nil)
    archive_link = self.github.archive_link(strip_github_path(repo_url), {:ref => ref})

    IO.copy_stream(open(archive_link), "#{dir}/#{filename}")

    raise(IOError, "#{dir}/#{filename} does not exist") unless FileTest.exists?("#{dir}/#{filename}")

    exit_msg = `tar xzf #{dir}/#{filename} -C #{dir} 2>&1`
    raise(IOError, exit_msg) if $?.to_i != 0

    yield Dir.glob("#{dir}/*/").max_by {|f| File.mtime(f)}
  rescue StandardError => e
    Rails.logger.error "Error inside_github_archive #{e.message}" unless Rails.env == 'test'
    raise e
  ensure
    FileUtils.remove_entry_secure(dir)
  end

  def self.get_service_info service_name
    url_string = "#{Setting.service_portal_host}/services/#{service_name}.json"
    response = RestClient.get(url_string)
    return JSON.parse(response.body)
  end

  def self.get_code_lang repo_url
    self.github.languages(strip_github_path(repo_url)).to_hash.stringify_keys
  end

  def self.get_head_commit repo_url
    self.github.commits(strip_github_path(repo_url)).first.sha
  end

  def self.tally_code dir, languages
    num_files, num_lines = 0, 0

    languages.each do |lang|
      case lang
      when 'Ruby'
        filelist = ['Gemfile','Gemfile.lock','*.rb','*.haml','*.erb']
      when 'JavaScript'
        filelist = ['package.json', '*.js']
      when 'CoffeeScript'
        filelist = ['package.json']
      when 'Java'
        filelist = ['*.java']
      when 'Python'
        filelist = ['*.py']
      else
        filelist = []
      end

      filelist.each do |files|
        exclude = ''
        exclude = "-not -path #{dir}/node_modules/*" if files == '*.js'
        files_found = `find #{dir}/ -name #{files} #{exclude}| wc -l`.to_i
        num_files += files_found
        if files_found > 0
          num_lines += `find #{dir}/ -name #{files} #{exclude}| xargs wc -l`.split("\n").last.split[0].to_i
        end
      end
    end

    return num_files, num_lines
  end

  def self.get_stats
    {
      :services => Service.joins(:burns).where('burns.service_id = services.id').distinct.count,
      :burns => Burn.count,
      :total_findings => Finding.count,
      :open_findings => Finding.status(Finding.status_code[:open]).count,
      :hidden_findings => Finding.status(Finding.status_code[:hidden]).count,
      :published_findings => Finding.status(Finding.status_code[:published]).count,
      :filtered_findings => Finding.status(Finding.status_code[:filtered]).count,
      :files => Burn.sum(:num_files),
      :lines => Burn.sum(:num_lines)
    }
  end

  def self.get_burn_list
    burns = Burn.page(1).per(10).order('burns.id DESC')
    return pack_service_name(burns)
  end

  def self.get_services
    return Service.has_burns.order("services.pretty_name ASC").as_json
  end

  def self.pack_service_name objects
    results = []

    objects.each do |result|
      result_hash = result.attributes
      result_hash[:service_name] = result.service.pretty_name
      results << result_hash
    end
    return results
  end

  def self.pack_finding_count objects
    results = []

    objects.each do |result|
      result_hash = result.attributes
      result_hash[:finding_count] = Finding.filtered_by(result.id).count
      results << result_hash
    end
    return results
  end

  def self.get_service_stats service_id
    service = Service.find(service_id)
    findings = Finding.service_id(service.id)
    return {
      :burns => Burn.service_id(service.id).count,
      :open_findings => findings.status(Finding.status_code[:open]).count,
      :total_findings => findings.count,
      :filtered_findings => findings.status(Finding.status_code[:filtered]).count,
      :hidden_findings => findings.status(Finding.status_code[:hidden]).count,
      :published_findings => findings.status(Finding.status_code[:published]).count
    }
  end

  def self.update_service_stats id
    service = Service.find(id)
    stats = CodeburnerUtil.get_service_stats(service.id).merge({
      :service_id => id
    })

    service_stat = ServiceStat.where(:service_id => service.id).first

    if service_stat.nil?
      service_stat = ServiceStat.create(:service_id => service.id)
    end

    service_stat.update(stats)
    Rails.cache.write('services', CodeburnerUtil.get_services)
  end

  def self.update_system_stats
    stats = get_stats
    system_stat = SystemStat.first
    if system_stat.nil?
      SystemStat.create(stats)
    else
      system_stat.update(stats)
    end

    Rails.cache.write("stats", stats)
    Rails.cache.write("history_range", get_history_range)
  end

  def self.history_resolution start_date, end_date
    case end_date - start_date
    when 0..12.hours.to_i then
      1.hour
    when 12.hours.to_i..3.day.to_i then
      4.hour
    when 3.days.to_i..14.days.to_i then
      12.hours
    when 14.days.to_i..1.month.to_i then
      1.day
    when 1.month.to_i..2.months.to_i then
      3.days
    when 2.months.to_i..6.months.to_i then
      5.days
    else
      1.week
    end
  end

  def self.get_stepped_history stat_object, requested_stats, start_date, end_date, resolution
    timestep = start_date
    results = {}

    while timestep < (end_date + resolution)
      timestep = end_date if timestep > end_date
      version = stat_object.version_at(timestep).attributes.deep_symbolize_keys
      requested_stats.each do |stat|
        results[stat] = [] if results[stat].nil?
        results[stat] << [timestep, version[stat]]
      end
      timestep = timestep + resolution
    end

    return results
  end

  def self.get_burn_history start_date=nil, end_date=nil, service_id=nil
    results = []
    first_burn = Burn.service_id(service_id).first.created_at
    if start_date.nil?
      start_date = Date.new(first_burn.year, first_burn.month, first_burn.day)
    else
      start_date = DateTime.parse(start_date)
    end
    if end_date.nil?
      end_date = Date.new(Time.now.year, Time.now.month, Time.now.day)
    else
      end_date = DateTime.parse(end_date)
    end

    start_date.upto(end_date) do |date|
      results << [date, Burn.service_id(service_id).where(created_at: date.beginning_of_day..date.end_of_day).count]
    end

    results
  end

  def self.get_history_range id=nil
    if id.nil?
      stat = SystemStat.first
    else
      stat = Service.find(id).service_stat
    end
    start_date = stat.versions.first.created_at
    end_date = Time.now()

    return {:start_date => start_date, :end_date => end_date, :resolution => history_resolution(start_date, end_date)}
  end

  def self.get_history start_date=nil, end_date=nil, resolution=nil, requested_stats=nil, service_id=nil
    if service_id.nil?
      stat = SystemStat.first
    else
      stat = ServiceStat.where(service_id: service_id).first
    end
    requested_stats = [:services, :burns, :total_findings, :open_findings, :hidden_findings, :published_findings, :filtered_findings, :files, :lines] if requested_stats.nil?
    if start_date.nil? or start_date < stat.versions.first.created_at
      start_date = stat.versions.first.created_at
    else
      start_date = Time.parse(start_date)
    end
    if end_date.nil? or end_date > Time.now
      end_date = Time.now
    else
      end_date = Time.parse(end_date)
    end
    if resolution.nil?
      resolution = history_resolution(start_date.to_i, end_date.to_i)
    else
      resolution = resolution.to_i
    end
    timestep = start_date
    results = {}

    return get_stepped_history stat, requested_stats, start_date, end_date, resolution
  end
end
