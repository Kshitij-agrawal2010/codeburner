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
class Api::FilterController < ApplicationController
  respond_to :json

  # START ServiceDiscovery
  # resource: filters.index
  # description: Show all filters
  # method: GET
  # path: /filter
  #
  # response:
  #   name: filters
  #   description: a hash containing a result count and list of filters
  #   type: object
  #   properties:
  #     count:
  #       type: integer
  #       description: number of results
  #     results:
  #       type: array
  #       descritpion: the list of filters
  #       items:
  #         $ref: filters.show.response
  # END ServiceDiscovery
  def index
    safe_sorts = ['id', 'repo_id' ]
    sort_by = 'filters.id'
    order = nil

    sort_by = "#{params[:sort_by]}" if safe_sorts.include? params[:sort_by]

    if params.has_key?(:order)
      order = params[:order].upcase if ['ASC','DESC'].include? params[:order].upcase
    end

    if params.has_key?(:sort_by) or params.has_key?(:per_page) or params.has_key?(:page)
      result_objects = Filter.all.order("#{sort_by} #{order}") \
        .page(params[:page]) \
        .per(params[:per_page])
      count = result_objects.total_count
    else
      result_objects = Filter.all
      count = result_objects.count
    end

    results  = CodeburnerUtil.pack_finding_count(result_objects)

    if params.has_key?(:sort_by) and params[:sort_by] == 'finding_count'
      results = results.sort_by { |hash| hash[:finding_count] }.reverse
    end

    render(:json => {count: count, results: results})
  end

  # START ServiceDiscovery
  # resource: filters.show
  # description: Show a filter
  # method: GET
  # path: /filter/:id
  #
  # request:
  #   parameters:
  #     id:
  #       type: integer
  #       descritpion: Filter ID
  #       location: url
  #       required: true
  #
  # response:
  #   name: filter
  #   description: a filter object
  #   type: object
  #   properties:
  #     id:
  #       type: integer
  #       description: filter ID
  #     repo_id:
  #       type: integer
  #       descritpion: the repo ID
  #     severity:
  #       type: integer
  #       description: severity to filter (0 - 3)
  #     fingerprint:
  #       type: string
  #       description: the SHA256 fingerprint to filter
  #     scanner:
  #       type: string
  #       description: a specific scanning software to filter
  #     description:
  #       type: string
  #       description: finding description to filter
  #     detail:
  #       type: string
  #       description: finding detail text to filter
  #     file:
  #       type: string
  #       description: file name to filter
  #     line:
  #       type: string
  #       description: line number or range to filter
  #     code:
  #       type: text
  #       description: the code snipper to filter
  # END ServiceDiscovery
  def show
    results = Filter.find(params[:id])

    render(:json => results)
  rescue ActiveRecord::RecordNotFound
    render(:json => {error: "no filter with that id found}"}, :status => 404)
  end

  # START ServiceDiscovery
  # resource: filters.create
  # description: Create a filter
  # method: POST
  # path: /filter
  #
  # request:
  #   parameters:
  #     repo_id:
  #       type: integer
  #       descritpion: repo_id to filter
  #       location: body
  #       required: false
  #     severity:
  #       type: integer
  #       description: severity to filter
  #       location: body
  #       required: false
  #     fingerprint:
  #       type: string
  #       description: fingerprint to filter
  #       location: body
  #       required: false
  #     scanner:
  #       type: string
  #       description: scanner to filter
  #       location: body
  #       required: false
  #     description:
  #       type: string
  #       description: description to filter
  #       location: body
  #       required: false
  #     detail:
  #       type: string
  #       description: detail to filter
  #       location: body
  #       required: false
  #     file:
  #       type: string
  #       description: file name to filter
  #       location: body
  #       required: false
  #     line:
  #       type: string
  #       description: line number or range to filter
  #       location: body
  #       required: false
  #     code:
  #       type: text
  #       description: code snippet to filter
  #       location: body
  #       required: false
  #
  # response:
  #   name: filter
  #   description: a filter object
  #   type: object
  #   properties:
  #     $ref: filters.show.response
  # END ServiceDiscovery
  def create
    filter = Filter.new({
      :repo_id => params[:repo_id],
      :severity => params[:severity],
      :fingerprint => params[:fingerprint],
      :scanner => params[:scanner],
      :description => params[:description],
      :detail => params[:detail],
      :file => params[:file],
      :line => params[:line],
      :code => params[:code]
      })

    if filter.valid?
      filter.save
      filter.filter_existing!
      render(:json => filter.to_json)
    else
      render(:json => {error: filter.errors[:base]}, :status => 409)
    end
  end

  # START ServiceDiscovery
  # resource: filters.destroy
  # description: Delete a specific filter
  # method: DELETE
  # path: /filter/:id
  #
  # request:
  #   parameters:
  #     id:
  #       type: integer
  #       descritpion: Filter ID
  #       location: url
  #       required: true
  #
  # response:
  #   name: result
  #   description: result success or error w/ msg
  # END ServiceDiscovery
  def destroy
    return render(:json => {error: "bad request"}, :status => 400) unless params.has_key?(:id)

    filter = Filter.find(params[:id])
    filtered_by = Finding.filtered_by(filter.id)
    repo_ids = []
    filtered_by.each {|finding| repo_ids << finding.repo_id}
    repo_ids.uniq.each do |repo_id|
      CodeburnerUtil.update_repo_stats repo_id
    end

    filtered_by.update_all(status: 0, filter_id: nil)

    filter.destroy!

    Filter.all.each do |each_filter|
      each_filter.filter_existing!
    end

    render(:json => {result: "success"})
  rescue ActiveRecord::RecordNotFound
    render(:json => {error: "record not found for id = #{params[:id]}"}, :status => 404)
  end

end
