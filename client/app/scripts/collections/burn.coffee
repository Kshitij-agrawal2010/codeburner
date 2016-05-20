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
'use strict'

class Codeburner.Collections.Burn extends Backbone.PageableCollection
  model: Codeburner.Models.Burn
  url: '/api/burn'
  mode: 'server'
  state:
    pageSize: 10
    sortKey: 'count'
    order: 1
  queryParams:
    id: null
  filters:
    id: null


  parseState: (data) ->
    totalRecords: data.count

  parseRecords: (data) ->
    data.results

  resetFilter: ->
    @filters =
      id: null
    do @changeFilter

  changeFilter: ->
    query = []
    for key, value of @filters
      if $.isArray value
        data = value.join ','
      else
        data = value

      if data
        query.push "#{key}=#{data}"
        @queryParams[key] = data
      else
        @queryParams[key] = null
    Backbone.history.navigate "burns?#{query.join '&'}"
