{
  title: "ScopeStack - DEV",

  #   Alternative sample OAuth2 authentication. See more examples at https://docs.workato.com/developing-connectors/sdk/guides/authentication.html
  connection: {
    fields: [
      {
        name: "username",
        label: "Service Account Username",
        type: "string",
        control_type: "text",
        optional: false
      },
      {
        name: "password",
        label: "Service Account Password",
        type: "password",
        control_type: "password",
        optional: false
      }
    ],

    authorization: {
      type: "custom_auth",

      acquire: lambda do |connection|
        response = post("https://app.scopestack.io/oauth/token")
          .payload(
            grant_type: "password",
            client_id: "YOUR_SCOPESTACK_CLIENT_ID",
            client_secret: "YOUR_SCOPESTACK_CLIENT_SECRET",
            username: connection["username"],
            password: connection["password"]
          )
          .request_format_www_form_urlencoded

        user_response = get("https://api.scopestack.io/v1/me")
          .headers(
            "Authorization": "Bearer #{response['access_token']}",
            "Accept": "application/vnd.api+json"
          )

        account_slug = user_response.dig("data", "attributes", "account-slug")
        account_id   = user_response.dig("data", "attributes", "account-id")

        {
          access_token: response["access_token"],
          refresh_token: response["refresh_token"],
          refresh_token_expires_in: response["expires_in"],
          account_slug: account_slug,
          account_id: account_id
        }
      end,

      apply: lambda do |connection|
        headers(
          "Authorization": "Bearer #{connection['access_token']}",
          "Accept": "application/vnd.api+json"
        )
      end,

      refresh_on: [401, 403],

      refresh: lambda do |connection, refresh_token|
        response = post("https://app.scopestack.io/oauth/token")
          .payload(
            grant_type: "refresh_token",
            client_id: "YOUR_SCOPESTACK_CLIENT_ID",
            client_secret: "YOUR_SCOPESTACK_CLIENT_SECRET",
            refresh_token: refresh_token
          )
          .request_format_www_form_urlencoded

        account_slug = connection["account_slug"]
        account_id   = connection["account_id"]

        if !account_slug || !account_id
          user_response = get("https://api.scopestack.io/v1/me")
            .headers(
              "Authorization": "Bearer #{response['access_token']}",
              "Accept": "application/vnd.api+json"
            )

          account_slug ||= user_response.dig("data", "attributes", "account-slug")
          account_id   ||= user_response.dig("data", "attributes", "account-id")
        end

        {
          access_token: response["access_token"],
          refresh_token: response["refresh_token"],
          refresh_token_expires_in: response["expires_in"],
          account_slug: account_slug,
          account_id: account_id
        }
      end
    },

    base_uri: lambda do |connection|
      "https://api.scopestack.io"
    end
  },  

  test: lambda do |connection|
    # For custom_auth, the test function runs before token acquisition
    # The acquire function already validates the connection by making a successful API call
    # So we can simply return true here
    true
  end,

  picklists: {
    clients: lambda do |connection|
      puts "Connection details: #{connection.inspect}"
      
      # Get account information using the reusable method
      account_info = call('get_account_info', connection)
      account_slug = account_info[:account_slug]

      puts "Fetching clients for account slug: #{account_slug}"

      # Get all clients
      response = get("/#{account_slug}/v1/clients")
                 .headers('Accept': 'application/vnd.api+json')
                 .after_error_response(/.*/) do |code, body, _header, message|
                   puts "Error fetching clients: #{code} - #{message}"
                   puts "Response body: #{body}"
                   error("Failed to fetch clients: #{message}: #{body}")
                 end

      puts "Got response: #{response.inspect}"

      if !response || !response['data']
        puts "Invalid response format: #{response.inspect}"
        error("Invalid response format from clients API")
      end

      # Format clients for picklist
      clients = response['data'].map do |client|
        [
          client['attributes']['name'],
          client['id']
        ]
      end

      puts "Formatted #{clients.length} clients for picklist"
      clients
    end,

    project_includes: lambda do |_connection|
      [
        ["Account", "account"],
        ["Business Unit", "business-unit"],
        ["Client", "client"],
        ["Creator", "creator"],
        ["Sales Executive", "sales-executive"],
        ["Presales Engineer", "presales-engineer"],
        ["Document Template", "document-template"],
        ["External Request", "external-request"],
        ["PSA Project", "psa-project"],
        ["Payment Term", "payment-term"],
        ["Rate Table", "rate-table"],
        ["CRM Opportunity", "crm-opportunity"],
        ["Approval Steps", "approval-steps"],
        ["Customer Successes", "customer-successes"],
        ["Notes", "notes"],
        ["Project Attachments", "project-attachments"],
        ["Project Collaborators", "project-collaborators"],
        ["Project Contacts", "project-contacts"],
        ["Project Conditions", "project-conditions"],
        ["Project Credits", "project-credits"],
        ["Project Documents", "project-documents"],
        ["Project Expenses", "project-expenses"],
        ["Project Governances", "project-governances"],
        ["Project Locations", "project-locations"],
        ["Project Products", "project-products"],
        ["Project Phases", "project-phases"],
        ["Project Resources", "project-resources"],
        ["Resource Plans", "resource-plans"],
        ["Project Services", "project-services"],
        ["Partner Requests", "partner-requests"],
        ["Project Versions", "project-versions"],
        ["Resource Rates", "resource-rates"],
        ["Quotes", "quotes"],
        ["Audit Logs", "audit-logs"],
        ["Pricing Adjustments", "pricing-adjustments"]
      ]
    end,

    project_statuses: lambda do |_connection|
      [
        ["Building", "building"],
        ["Technical Approval", "technical_approval"],
        ["Sales Approval", "sales_approval"],
        ["Business Approval", "business_approval"],
        ["Approved", "approved"],
        ["Won", "won"],
        ["Lost", "lost"],
        ["Canceled", "canceled"]
      ]
    end,

    active_questionnaires: lambda do |connection|
      begin
        puts "Starting active_questionnaires pick list"
        account_info = call('get_account_info', connection)
        puts "Account info: #{account_info.inspect}"
        account_slug = account_info[:account_slug]
        puts "Account slug: #{account_slug}"
  
        url = "https://api.scopestack.io/#{account_slug}/v1/questionnaires"
        puts "Making request to: #{url}"
        
        response = get(url)
          .headers('Accept': 'application/vnd.api+json')
          .after_error_response(/.*/) do |_code, body, _header, message|
            puts "Error response received: #{message}"
            puts "Error body: #{body}"
            error("Failed to fetch questionnaires: #{message}: #{body}")
          end
        
        puts "Response received: #{response.inspect}"
        questionnaires = response['data'] || []
        puts "Number of questionnaires found: #{questionnaires.length}"
  
        if questionnaires.empty?
          puts "No questionnaires found, returning test item"
          [["No questionnaires found (test item)", "test_id"]]
        else
          result = questionnaires.map do |q|
            label = q.dig('attributes', 'name') || "Questionnaire #{q['id']}"
            puts "Mapping questionnaire: #{label} (#{q['id']})"
            [label, q['id']]
          end
          puts "Final pick list items: #{result.inspect}"
          result
        end
      rescue => e
        puts "Exception caught: #{e.class} - #{e.message}"
        puts e.backtrace.join("\n")
        [["Error fetching questionnaires: #{e.message}", "error"]]
      end
    end,

    project_contact_variables: lambda do |connection|
      # Get account information using the reusable method
      account_info = call('get_account_info', connection)
      account_slug = account_info[:account_slug]

      # Get all project variables for contact context
      response = get("/#{account_slug}/v1/project-variables")
                .params('filter[variable-context]': 'project_contact')
                .headers('Accept': 'application/vnd.api+json')
                .after_error_response(/.*/) do |_code, body, _header, message|
                  error("Failed to fetch project variables: #{message}: #{body}")
                end

      # Transform the response into a pick list format
      response['data'].map do |variable|
        {
          name: variable['attributes']['name'],
          label: variable['attributes']['label'],
          value: variable['attributes']['name']
        }
      end
    end,


  },

  object_definitions: {
    #  Object definitions can be referenced by any input or output fields in actions/triggers.
    #  Use it to keep your code DRY. Possible arguments - connection, config_fields
    #  See more at https://docs.workato.com/developing-connectors/sdk/sdk-reference/object_definitions.html

    project: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Project ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "project-name", type: "string", label: "Project Name" },
              { name: "executive-summary", type: "string", label: "Executive Summary" },
              { name: "key-objectives", type: "string", label: "Key Objectives" },
              { name: "our-responsibilities", type: "string", label: "Our Responsibilities" },
              { name: "client-responsibilities", type: "string", label: "Client Responsibilities" },
              { name: "solution-summary", type: "string", label: "Solution Summary" },
              { name: "out-of-scope", type: "string", label: "Out of Scope" },
              { name: "one-time-adjustment", type: "integer", label: "One Time Adjustment" },
              { name: "mrr-adjustment", type: "integer", label: "MRR Adjustment" },
              { name: "mrr-terms", type: "integer", label: "MRR Terms" },
              { name: "cola", type: "number", label: "COLA" },
              { name: "recurring-billing-frequency", type: "string", label: "Recurring Billing Frequency" },
              { name: "include-ps-revenue-in-mrr", type: "string", label: "Include PS Revenue in MRR" },
              { name: "service-start-date", type: "date", label: "Service Start Date" },
              { name: "travel-limit", type: "integer", label: "Travel Limit" },
              { name: "status", type: "string", label: "Status" },
              { name: "submitted-at", type: "date_time", label: "Submitted At" },
              { name: "approved-at", type: "date_time", label: "Approved At" },
              { name: "msa-date", type: "date", label: "MSA Date" },
              { name: "created-at", type: "date_time", label: "Created At" },
              { name: "updated-at", type: "date_time", label: "Updated At" },
              {
            name: "project-variables",
            type: "array",
            of: "object",
            properties: [
              { name: "name", type: "string", label: "Name" },
              { name: "label", type: "string", label: "Label" },
              { name: "variable_type", type: "string", label: "Variable Type" },
              { name: "minimum", type: "integer", label: "Minimum" },
              { name: "maximum", type: "integer", label: "Maximum" },
              { name: "required", type: "boolean", label: "Required" },
              {
                name: "select_options",
                type: "array",
                of: "object",
                properties: [
                  { name: "key", type: "string", label: "Key" },
                  { name: "value", type: "string", label: "Value" },
                  { name: "default", type: "boolean", label: "Default" }
                ]
              },
              { name: "position", type: "integer", label: "Position" },
              { name: "context", type: "string", label: "Context" },
              { name: "uuid", type: "string", label: "UUID" },
              { name: "value", type: "string", label: "Value" }
            ]
              },
              {
                name: "field-labels",
                type: "object",
                properties: [
                  { name: "executive_summary", type: "string", label: "Executive Summary" },
                  { name: "solution_summary", type: "string", label: "Solution Summary" },
                  { name: "customer_summary", type: "string", label: "Customer Summary" },
                  { name: "customer_success", type: "string", label: "Customer Success" },
                  { name: "presales_engineer", type: "string", label: "Presales Engineer" },
                  { name: "client", type: "string", label: "Client" },
                  { name: "business_unit", type: "string", label: "Business Unit" },
                  { name: "location", type: "string", label: "Location" },
                  { name: "our_responsibilities", type: "string", label: "Our Responsibilities" },
                  { name: "client_responsibilities", type: "string", label: "Client Responsibilities" },
                  { name: "out_of_scope", type: "string", label: "Out of Scope" }
                ]
              },
              { name: "tag-list", type: "array", of: "string", label: "Tag List" },
              { name: "client-name", type: "string", label: "Client Name" },
              { name: "presales-engineer-name", type: "string", label: "Presales Engineer Name" },
              {
                name: "payment-info",
                type: "object",
                properties: [
                  { name: "pricing-model", type: "string", label: "Pricing Model" },
                  { name: "include-expenses", type: "boolean", label: "Include Expenses" },
                  { name: "include-product", type: "boolean", label: "Include Product" },
                  { name: "rate-type", type: "string", label: "Rate Type" }
                ]
              }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "account",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "business-unit",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "client",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "document-template",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "external-request",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "sales-executive",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "presales-engineer",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "psa-project",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "crm-opportunity",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "payment-term",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "user",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-attachments",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-collaborators",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-contacts",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-conditions",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-credits",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-documents",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-expenses",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-governances",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-locations",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-materials",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-phases",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-products",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-resources",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-versions",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "project-services",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "rate-table",
                type: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "resource-plans",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "approval-steps",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "notes",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "quotes",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "partner-requests",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "audit-logs",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              },
              {
                name: "customer-successes",
                type: "array",
                of: "object",
                properties: [
                  { name: "links", type: "object", properties: [{ name: "self", type: "string" }, { name: "related", type: "string" }] },
                  { name: "data", type: "array", of: "object", properties: [{ name: "id", type: "integer" }, { name: "type", type: "string" }] }
                ]
              }
            ]
          }
        ]
      end
    },

    client: {
      fields: lambda do |connection, config_fields, object_definitions|
        [
          {
            name: "id",
            label: "Client ID",
            type: "string",
            control_type: "text",
            hint: "The unique identifier of the client"
          },
          {
            name: "type",
            label: "Type",
            type: "string",
            control_type: "text",
            hint: "The type of the resource (always 'clients')"
          },
          {
            name: "active",
            label: "Active",
            type: "boolean",
            control_type: "checkbox",
            hint: "Whether the client is active"
          },
          {
            name: "name",
            label: "Client Name",
            type: "string",
            control_type: "text",
            hint: "The name of the client"
          },
          {
            name: "msa_date",
            label: "MSA Date",
            type: "string",
            control_type: "date",
            hint: "The date of the Master Services Agreement"
          },
          {
            name: "domain",
            label: "Domain",
            type: "string",
            control_type: "text",
            hint: "The domain associated with the client"
          },
          {
            name: "user-defined-fields",
            label: "User Defined Fields",
            type: "array",
            of: "object",
            properties: [
              {
                name: "name",
                label: "Field Name",
                type: "string",
                hint: "The unique identifier for this user defined field"
              },
              {
                name: "label",
                label: "Field Label",
                type: "string",
                hint: "The display name for this field"
              },
              {
                name: "variable_type",
                label: "Variable Type",
                type: "string",
                hint: "The type of variable (e.g., text, number, select)"
              },
              {
                name: "minimum",
                label: "Minimum Value",
                type: "number",
                hint: "The minimum allowed value for numeric variables",
                optional: true
              },
              {
                name: "maximum",
                label: "Maximum Value",
                type: "number",
                hint: "The maximum allowed value for numeric variables",
                optional: true
              },
              {
                name: "required",
                label: "Required",
                type: "boolean",
                hint: "Whether this field must be provided"
              },
              {
                name: "select_options",
                label: "Select Options",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "key",
                    label: "Key",
                    type: "string",
                    hint: "The option key/value"
                  },
                  {
                    name: "value",
                    label: "Value",
                    type: "string",
                    hint: "The option label"
                  },
                  {
                    name: "default value",
                    label: "Default",
                    type: "boolean",
                    hint: "Whether this is the default option",
                    optional: true
                  }
                ],
                hint: "Available options for select type fields",
                optional: true
              },
              {
                name: "position",
                label: "Position",
                type: "integer",
                hint: "The display order of this field"
              },
              {
                name: "context",
                label: "Context",
                type: "string",
                hint: "The context this field belongs to (e.g., 'client')"
              },
              {
                name: "uuid",
                label: "UUID",
                type: "string",
                hint: "Unique identifier for this field definition"
              },
              {
                name: "value",
                label: "Value",
                type: "string",
                hint: "The current value of this field for this client",
                optional: true
              }
            ],
            hint: "User defined fields associated with the client. Only present in responses.",
            optional: true
          },
          {
            name: "links",
            label: "Links",
            type: "object",
            properties: [
              {
                name: "self",
                label: "Self Link",
                type: "string",
                control_type: "url",
                hint: "The URL to this client resource"
              }
            ]
          },
          {
            name: "relationships",
            label: "Relationships",
            type: "object",
            properties: [
              {
                name: "account",
                label: "Account",
                type: "object",
                properties: [
                  {
                    name: "links",
                    label: "Account Links",
                    type: "object",
                    properties: [
                      {
                        name: "self",
                        label: "Self Link",
                        type: "string",
                        control_type: "url",
                        hint: "The URL to this relationship"
                      },
                      {
                        name: "related",
                        label: "Related Link",
                        type: "string",
                        control_type: "url",
                        hint: "The URL to the related account"
                      }
                    ]
                  }
                ]
              },
              {
                name: "rate_table",
                label: "Rate Table",
                type: "object",
                properties: [
                  {
                    name: "links",
                    label: "Rate Table Links",
                    type: "object",
                    properties: [
                      {
                        name: "self",
                        label: "Self Link",
                        type: "string",
                        control_type: "url",
                        hint: "The URL to this relationship"
                      },
                      {
                        name: "related",
                        label: "Related Link",
                        type: "string",
                        control_type: "url",
                        hint: "The URL to the related rate table"
                      }
                    ]
                  }
                ]
              },
              {
                name: "contacts",
                label: "Contacts",
                type: "object",
                properties: [
                  {
                    name: "links",
                    label: "Contacts Links",
                    type: "object",
                    properties: [
                      {
                        name: "self",
                        label: "Self Link",
                        type: "string",
                        control_type: "url",
                        hint: "The URL to this relationship"
                      },
                      {
                        name: "related",
                        label: "Related Link",
                        type: "string",
                        control_type: "url",
                        hint: "The URL to the related contacts"
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    contact: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Contact ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "name", type: "string", label: "Contact Name" },
              { name: "phone", type: "string", label: "Phone Number" },
              { name: "email", type: "string", label: "Email Address" },
              { name: "title", type: "string", label: "Title" }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "client",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Client ID" },
                      { name: "type", type: "string", label: "Client Type" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    sales_executive: {
      fields: lambda do |_connection, _config_fields|
        [
          { 
            name: "id", 
            type: "string", 
            label: "Sales Executive ID",
            control_type: "text",
            optional: true,
            hint: "If provided, updates the existing sales executive. If the sales executive is not found, the action will fail. If not provided, creates a new one."
          },
          { 
            name: "name", 
            type: "string", 
            label: "Sales Executive Name",
            control_type: "text",
            optional: true,
            hint: "Full name of the sales executive. Required for creation if email is not provided."
          },
          { 
            name: "email", 
            type: "string", 
            label: "Sales Executive Email",
            control_type: "email",
            optional: true,
            hint: "Email address of the sales executive. Required for creation if name is not provided."
          },
          { 
            name: "title", 
            type: "string", 
            label: "Sales Executive Title",
            control_type: "text",
            optional: true,
            hint: "Job title of the sales executive"
          },
          { 
            name: "phone", 
            type: "string", 
            label: "Sales Executive Phone",
            control_type: "phone",
            optional: true,
            hint: "Phone number of the sales executive"
          }
        ]
      end
    },

    presales_engineer: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Presales Engineer ID" },
          { name: "email", type: "string", label: "Presales Engineer Email" }
        ]
      end
    },

    questionnaire: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Questionnaire ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "links",
            type: "object",
            properties: [
              { name: "self", type: "string", label: "Self Link" }
            ]
          },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "active", type: "boolean", label: "Active" },
              { name: "name", type: "string", label: "Name" },
              { name: "published", type: "boolean", label: "Published" },
              { name: "created-at", type: "date_time", label: "Created At" },
              { name: "slug", type: "string", label: "Slug" },
              { name: "introduction", type: "string", label: "Introduction" },
              { name: "thank-you", type: "string", label: "Thank You Message" },
              { name: "completion-url", type: "string", label: "Completion URL" },
              { 
                name: "questions",
                type: "array",
                of: "object",
                properties: [
                  { name: "id", type: "integer", label: "Question ID" },
                  { name: "question", type: "string", label: "Question Text" },
                  { name: "name", type: "string", label: "Question Name" },
                  { name: "slug", type: "string", label: "Question Slug" },
                  { name: "position", type: "integer", label: "Position" },
                  { name: "value-type", type: "string", label: "Value Type" },
                  { name: "required", type: "boolean", label: "Required" },
                  { 
                    name: "settings",
                    type: "object",
                    properties: [
                      { name: "max", type: "string", label: "Maximum Value" },
                      { name: "min", type: "string", label: "Minimum Value" },
                      { name: "step", type: "string", label: "Step Value" }
                    ]
                  },
                  {
                    name: "select-options",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "key", type: "string", label: "Option Key" },
                      { name: "value", type: "string", label: "Option Value" },
                      { name: "default", type: "boolean", label: "Is Default" }
                    ]
                  },
                  { name: "deleted-at", type: "date_time", label: "Deleted At", optional: true },
                  { name: "uuid", type: "string", label: "UUID" },
                  { name: "questionnaire-section-id", type: "string", label: "Section ID" }
                ]
              },
              {
                name: "sections",
                type: "array",
                of: "object",
                properties: [
                  { name: "id", type: "integer", label: "Section ID" },
                  { name: "name", type: "string", label: "Section Name" },
                  { name: "expression", type: "string", label: "Expression", optional: true },
                  { name: "position", type: "integer", label: "Position" },
                  { name: "introduction", type: "string", label: "Introduction", optional: true }
                ]
              },
              { 
                name: "tag-list",
                type: "array",
                of: "string",
                label: "Tags"
              },
              {
                name: "teams",
                type: "array",
                of: "string",
                label: "Teams"
              }
            ]
          }
        ]
      end
    },

    survey: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Survey ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "links",
            type: "object",
            properties: [
              { name: "self", type: "string", label: "Self Link" }
            ]
          },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "name", type: "string", label: "Name" },
              { name: "contact-name", type: "string", label: "Contact Name", optional: true },
              { name: "contact-email", type: "string", label: "Contact Email", optional: true },
              {
                name: "responses",
                type: "array",
                of: "object",
                properties: [
                  { name: "name", type: "string", label: "Response Name", optional: true },
                  { name: "slug", type: "string", label: "Response Slug", optional: true },
                  { name: "question", type: "string", label: "Question" },
                  { name: "answer", type: "string", label: "Answer", optional: true },
                  { name: "value-type", type: "string", label: "Value Type" },
                  { name: "position", type: "integer", label: "Position" },
                  { name: "required", type: "boolean", label: "Required" },
                  { name: "survey-response-id", type: "integer", label: "Survey Response ID", optional: true },
                  { name: "question-id", type: "integer", label: "Question ID" },
                  {
                    name: "select-options",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "key", type: "string", label: "Option Key" },
                      { name: "value", type: "string", label: "Option Value" },
                      { name: "default", type: "boolean", label: "Is Default" }
                    ]
                  }
                ]
              },
              {
                name: "recommendations",
                type: "array",
                of: "object",
                properties: [
                  { name: "id", type: "integer", label: "Recommendation ID" },
                  { name: "survey_id", type: "integer", label: "Survey ID" },
                  { name: "questionnaire_recommendation_id", type: "integer", label: "Questionnaire Recommendation ID" },
                  { name: "target_type", type: "string", label: "Target Type" },
                  { name: "target_id", type: "integer", label: "Target ID" },
                  { name: "resource_id", type: "integer", label: "Resource ID" },
                  { name: "quantity", type: "string", label: "Quantity" },
                  { name: "status", type: "string", label: "Status" },
                  { name: "created_at", type: "date_time", label: "Created At" },
                  { name: "updated_at", type: "date_time", label: "Updated At" },
                  { name: "project_resource_id", type: "integer", label: "Project Resource ID" },
                  { name: "uuid", type: "string", label: "UUID" },
                  { name: "item_id", type: "integer", label: "Item ID" },
                  { name: "item_type", type: "string", label: "Item Type" },
                  {
                    name: "refinements",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Refinement ID" },
                      { name: "target_type", type: "string", label: "Target Type" },
                      { name: "target_id", type: "integer", label: "Target ID" },
                      { name: "resource_id", type: "integer", label: "Resource ID" },
                      { name: "quantity", type: "integer", label: "Quantity" },
                      { name: "status", type: "string", label: "Status" },
                      { name: "project_resource_id", type: "integer", label: "Project Resource ID" },
                      { name: "uuid", type: "string", label: "UUID" },
                      { name: "item_type", type: "string", label: "Item Type" },
                      { name: "item_id", type: "integer", label: "Item ID" }
                    ]
                  }
                ]
              },
              { name: "updated-at", type: "date_time", label: "Updated At" },
              { name: "created-at", type: "date_time", label: "Created At" },
              { name: "status", type: "string", label: "Status" },
              { name: "emails", type: "string", label: "Emails" },
              { name: "sender", type: "string", label: "Sender" },
              { name: "sent-at", type: "date_time", label: "Sent At", optional: true },
              {
                name: "calculations",
                type: "array",
                of: "object",
                properties: [
                  { name: "calculation_id", type: "integer", label: "Calculation ID" },
                  { name: "value", type: "string", label: "Value" }
                ]
              },
              { name: "user-id", type: "integer", label: "User ID" },
              { name: "completed-by", type: "string", label: "Completed By" }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "account",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "questionnaire",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project-survey",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "survey-responses",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "survey-recommendations",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    business_unit: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Business Unit ID" },
          { name: "type", type: "string", label: "Type" },
              {
                name: "attributes",
                type: "object",
                properties: [
              { name: "name", type: "string", label: "Name" },
              { name: "external-name", type: "string", label: "External Name" },
              { name: "street-address", type: "string", label: "Street Address" },
              { name: "street2", type: "string", label: "Street 2" },
              { name: "city", type: "string", label: "City" },
              { name: "state", type: "string", label: "State" },
              { name: "postal-code", type: "string", label: "Postal Code" },
              { name: "country", type: "string", label: "Country" }
                ]
              },
              {
                name: "relationships",
                type: "object",
                properties: [
                  {
                name: "account",
                    type: "object",
                    properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                      {
                        name: "data",
                        type: "object",
                        properties: [
                      { name: "id", type: "integer", label: "Account ID" },
                      { name: "type", type: "string", label: "Account Type" }
                    ]
                  }
                ]
              },
              {
                name: "clients",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Client ID" },
                      { name: "type", type: "string", label: "Client Type" }
                    ]
                  }
                ]
              },
              {
                name: "crm-opportunities",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Opportunity ID" },
                      { name: "type", type: "string", label: "Opportunity Type" }
                ]
              }
            ]
          },
          {
                name: "document-templates",
            type: "array",
            of: "object",
            properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Document Template ID" },
                      { name: "type", type: "string", label: "Document Template Type" }
                    ]
                  }
                ]
              },
              {
                name: "expense-categories",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Expense Category ID" },
                      { name: "type", type: "string", label: "Expense Category Type" }
                    ]
                  }
                ]
              },
              {
                name: "governances",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Governance ID" },
                      { name: "type", type: "string", label: "Governance Type" }
                    ]
                  }
                ]
              },
              {
                name: "payment-credits",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Payment Credit ID" },
                      { name: "type", type: "string", label: "Payment Credit Type" }
                    ]
                  }
                ]
              },
              {
                name: "payment-terms",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Payment Term ID" },
                      { name: "type", type: "string", label: "Payment Term Type" }
                    ]
                  }
                ]
              },
              {
                name: "phases",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Phase ID" },
                      { name: "type", type: "string", label: "Phase Type" }
                    ]
                  }
                ]
              },
              {
                name: "products",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Product ID" },
                      { name: "type", type: "string", label: "Product Type" }
                    ]
                  }
                ]
              },
              {
                name: "project-variables",
                type: "array",
                label: "Project Variables",
                hint: "Variables associated with the product. Only present in responses.",
                optional: true,
                of: "object",
                properties: [
                  { 
                    name: "name", 
                    type: "string", 
                    label: "Variable Name",
                    hint: "The unique identifier for this variable"
                  },
                  { 
                    name: "label", 
                    type: "string", 
                    label: "Variable Label",
                    hint: "The display name for this variable"
                  },
                  { 
                    name: "variable_type", 
                    type: "string", 
                    label: "Variable Type",
                    hint: "The type of variable (e.g., text, number, select)"
                  },
                  { 
                    name: "minimum", 
                    type: "number", 
                    label: "Minimum Value",
                    hint: "The minimum allowed value for numeric variables",
                    optional: true 
                  },
                  { 
                    name: "maximum", 
                    type: "number", 
                    label: "Maximum Value",
                    hint: "The maximum allowed value for numeric variables",
                    optional: true 
                  },
                  { 
                    name: "required", 
                    type: "boolean", 
                    label: "Required",
                    hint: "Whether this variable must be provided"
                  },
                  {
                    name: "select_options",
                    type: "array",
                    of: "object",
                    label: "Select Options",
                    hint: "Available options for select-type variables",
                    properties: [
                      { 
                        name: "key", 
                        type: "string", 
                        label: "Option Key",
                        hint: "The value to be stored"
                      },
                      { 
                        name: "value", 
                        type: "string", 
                        label: "Option Value",
                        hint: "The display text for this option"
                      },
                      { 
                        name: "default", 
                        type: "boolean", 
                        label: "Default Option",
                        hint: "Whether this option should be selected by default"
                      }
                    ]
                  },
                  { 
                    name: "position", 
                    type: "integer", 
                    label: "Position",
                    hint: "The order in which this variable should be displayed"
                  },
                  { 
                    name: "context", 
                    type: "string", 
                    label: "Context",
                    hint: "The context in which this variable is used (e.g., 'product')"
                  },
                  { 
                    name: "uuid", 
                    type: "string", 
                    label: "UUID",
                    hint: "The unique identifier for this variable instance"
                  },
                  { 
                    name: "value", 
                    type: "string", 
                    label: "Value",
                    hint: "The current value of this variable",
                    optional: true 
                  }
                ]
              },
              {
                name: "projects",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Project ID" },
                      { name: "type", type: "string", label: "Project Type" }
                    ]
                  }
                ]
              },
              {
                name: "rate-tables",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Rate Table ID" },
                      { name: "type", type: "string", label: "Rate Table Type" }
                    ]
                  }
                ]
              },
              {
                name: "resources",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Resource ID" },
                      { name: "type", type: "string", label: "Resource Type" }
                    ]
                  }
                ]
              },
              {
                name: "service-categories",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Service Category ID" },
                      { name: "type", type: "string", label: "Service Category Type" }
                    ]
                  }
                ]
              },
              {
                name: "services",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Service ID" },
                      { name: "type", type: "string", label: "Service Type" }
                    ]
                  }
                ]
              },
              {
                name: "teams",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Team ID" },
                      { name: "type", type: "string", label: "Team Type" }
                    ]
                  }
                ]
              },
              {
                name: "users",
                type: "array",
                of: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "id", type: "integer", label: "User ID" },
                      { name: "type", type: "string", label: "User Type" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    crm_opportunity: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: "id",
            type: "string",
            control_type: "text",
            label: "Opportunity ID",
            hint: "The Opportunity ID in ScopeStack. Leave blank to create new, or provide an ID to update existing",
            optional: true
          },
          {
            name: "opportunity-id",
            type: "string",
            control_type: "text",
            label: "CRM Opportunity ID",
            hint: "The ID of the opportunity in the foreign CRM",
            optional: false
          },
          {
            name: "name",
            type: "string",
            control_type: "text",
            label: "Name",
            hint: "The name of the opportunity in the foreign CRM",
            optional: false
          },
          {
            name: "display-name-override",
            type: "string",
            control_type: "text",
            label: "Display Name Override",
            hint: "Optional override for the automatically generated display name (Account Name / Opp Name / Opp ID)",
            optional: true
          },
          {
            name: "amount",
            type: "number",
            control_type: "number",
            label: "Amount",
            hint: "Monetary value of the opportunity in the foreign CRM",
            optional: true
          },
          {
            name: "stage",
            type: "string",
            control_type: "text",
            label: "Stage",
            hint: "Current stage of the opportunity in the foreign CRM",
            optional: true
          },
          {
            name: "is-closed",
            type: "string",
            control_type: "select",
            pick_list: [
              ["true", "true"],
              ["false", "false"]
            ],
            default: "false",
            toggle_hint: "Select from list",
            toggle_field: {
              name: "is-closed",
              label: "Is Closed",
              type: "string",
              control_type: "text",
              default: "false",
              toggle_hint: "Use custom value",
              hint: "Enter 'true' or 'false' (case insensitive)"
            }
          },
          {
            name: "owner-id",
            type: "string",
            control_type: "text",
            label: "Owner ID",
            hint: "ID of the opportunity owner in the foreign CRM",
            optional: true
          },
          {
            name: "owner-name",
            type: "string",
            control_type: "text",
            label: "Owner Name",
            hint: "Name of the opportunity owner in the foreign CRM",
            optional: true
          },
          {
            name: "account-id",
            type: "string",
            control_type: "text",
            label: "Account ID",
            hint: "ID of the associated client/account in the foreign CRM",
            optional: false
          },
          {
            name: "account-name",
            type: "string",
            control_type: "text",
            label: "Account Name",
            hint: "Name of the associated client/account in the foreign CRM",
            optional: false
          },
          {
            name: "location-name",
            type: "string",
            control_type: "text",
            label: "Location Name",
            hint: "Name of the opportunity's location in the foreign CRM",
            optional: true
          },
          {
            name: "street",
            type: "string",
            control_type: "text",
            label: "Street",
            hint: "Street address of the opportunity's location in the foreign CRM",
            optional: true
          },
          {
            name: "city",
            type: "string",
            control_type: "text",
            label: "City",
            hint: "City of the opportunity's location in the foreign CRM",
            optional: true
          },
          {
            name: "state",
            type: "string",
            control_type: "text",
            label: "State",
            hint: "State or province of the opportunity's location in the foreign CRM",
            optional: true
          },
          {
            name: "postal-code",
            type: "string",
            control_type: "text",
            label: "Postal Code",
            hint: "Postal or ZIP code of the opportunity's location in the foreign CRM",
            optional: true
          },
          {
            name: "country",
            type: "string",
            control_type: "text",
            label: "Country",
            hint: "Country code of the opportunity's location in the foreign CRM",
            optional: true
          }
        ]
      end
    },
    

    project_variable: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "active", type: "boolean", label: "Active" },
              { name: "label", type: "string", label: "Label" },
              { name: "name", type: "string", label: "Name" },
              { name: "variable-type", type: "string", label: "Variable Type" },
              { name: "minimum", type: "integer", label: "Minimum" },
              { name: "maximum", type: "integer", label: "Maximum" },
              { name: "required", type: "boolean", label: "Required" },
              { name: "position", type: "integer", label: "Position" },
              { name: "variable-context", type: "string", label: "Variable Context" },
              { 
                name: "select-options", 
                type: "array", 
                of: "object", 
                properties: [
                  { name: "key", type: "string", label: "Key" },
                  { name: "value", type: "string", label: "Value" },
                  { name: "default", type: "boolean", label: "Default" }
                ]
              }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "account",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    properties: [
                      { name: "id", type: "integer", label: "Account ID" },
                      { name: "type", type: "string", label: "Account Type" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Make the API call
        response = if input['search_by'] == 'id'
          get("/#{account_slug}/v1/project-variables/#{input['id']}")
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |_code, body, _header, message|
                      error("Failed to fetch project variable: #{message}: #{body}")
                    end
        else
          get("/#{account_slug}/v1/project-variables")
                    .params(filter: { name: input['name'] })
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |_code, body, _header, message|
                      error("Failed to fetch project variable: #{message}: #{body}")
                    end
        end

        response['data']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['project_variable']
      end
    },

    project_location: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "name", type: "string", label: "Location Name" },
              { name: "street", type: "string", label: "Street" },
              { name: "street2", type: "string", label: "Street 2" },
              { name: "city", type: "string", label: "City" },
              { name: "state", type: "string", label: "State" },
              { name: "postal-code", type: "string", label: "Postal Code" },
              { name: "country", type: "string", label: "Country" },
              { name: "remote", type: "boolean", label: "Remote" },
              { 
                name: "project-variables", 
                type: "array", 
                of: "object", 
                properties: [
                  { name: "name", type: "string", label: "Variable Name" },
                  { name: "value", type: "string", label: "Variable Value" }
                ]
              }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "project",
                type: "object",
                properties: [
                  { 
                    name: "data", 
                    type: "object", 
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "Project ID" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    document_template: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Document Template ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "links",
            type: "object",
            properties: [
              { name: "self", type: "string", label: "Self Link" }
            ]
          },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "active", type: "boolean", label: "Active" },
              { name: "name", type: "string", label: "Name" },
              { name: "format", type: "string", label: "Format" },
              { name: "merge-template-filename", type: "string", label: "Merge Template Filename" },
              { name: "merge-template", type: "string", label: "Merge Template" },
              { name: "filename-format", type: "array", of: "string", label: "Filename Format" },
              { name: "template-format", type: "string", label: "Template Format" }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "account",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    project_service_location: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "name", type: "string", label: "Location Name" },
              { name: "street", type: "string", label: "Street" },
              { name: "street2", type: "string", label: "Street 2" },
              { name: "city", type: "string", label: "City" },
              { name: "state", type: "string", label: "State" },
              { name: "postal-code", type: "string", label: "Postal Code" },
              { name: "country", type: "string", label: "Country" },
              { name: "remote", type: "boolean", label: "Remote" },
              { 
                name: "project-variables", 
                type: "array", 
                of: "object", 
                properties: [
                  { name: "name", type: "string", label: "Variable Name" },
                  { name: "value", type: "string", label: "Variable Value" }
                ]
              }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "project",
                type: "object",
                properties: [
                  { 
                    name: "data", 
                    type: "object", 
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "Project ID" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    tag: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "name", type: "string", label: "Tag Name" }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "account",
                type: "object",
                properties: [
                  { 
                    name: "data", 
                    type: "object", 
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "Account ID" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    project_contact: {
      fields: lambda do |_connection|
        [
          {
            name: 'id',
            label: 'ID',
            type: 'string'
          },
          {
            name: 'type',
            label: 'Type',
            type: 'string'
          },
          {
            name: 'active',
            label: 'Active',
            type: 'boolean'
          },
          {
            name: 'name',
            label: 'Name',
            type: 'string'
          },
          {
            name: 'title',
            label: 'Title',
            type: 'string'
          },
          {
            name: 'email',
            label: 'Email',
            type: 'string'
          },
          {
            name: 'phone',
            label: 'Phone',
            type: 'string'
          },
          {
            name: 'contact_type',
            label: 'Contact Type',
            type: 'string'
          },
          {
            name: 'project_variables',
            label: 'Project Variables',
            type: 'array',
            of: 'object',
            properties: [
              {
                name: 'name',
                label: 'Name',
                type: 'string'
              },
              {
                name: 'label',
                label: 'Label',
                type: 'string'
              },
              {
                name: 'variable_type',
                label: 'Variable Type',
                type: 'string'
              },
              {
                name: 'minimum',
                label: 'Minimum',
                type: 'string',
                optional: true
              },
              {
                name: 'maximum',
                label: 'Maximum',
                type: 'string',
                optional: true
              },
              {
                name: 'required',
                label: 'Required',
                type: 'boolean'
              },
              {
                name: 'select_options',
                label: 'Select Options',
                type: 'array',
                of: 'object',
                properties: [
                  {
                    name: 'key',
                    label: 'Key',
                    type: 'string'
                  },
                  {
                    name: 'value',
                    label: 'Value',
                    type: 'string'
                  },
                  {
                    name: 'default',
                    label: 'Default',
                    type: 'string',
                    optional: true
                  }
                ]
              },
              {
                name: 'position',
                label: 'Position',
                type: 'integer'
              },
              {
                name: 'context',
                label: 'Context',
                type: 'string'
              },
              {
                name: 'uuid',
                label: 'UUID',
                type: 'string'
              },
              {
                name: 'value',
                label: 'Value',
                type: 'string'
              }
            ]
          }
        ]
      end
    },

    product: {
      fields: lambda do |_connection, _config_fields|
        [
          { 
            name: "id", 
            type: "string", 
            label: "Product ID",
            hint: "The unique identifier of the product. Only present in responses."
          },
          { 
            name: "type", 
            type: "string", 
            label: "Type",
            hint: "Always 'products' for this resource type"
          },
          {
            name: "links",
            type: "object",
            label: "Resource Links",
            hint: "Links to related resources. Only present in responses.",
            properties: [
              { name: "self", type: "string", label: "Self Link" }
            ]
          },
          {
            name: "attributes",
            type: "object",
            properties: [
              { 
                name: "active", 
                type: "boolean", 
                label: "Active",
                hint: "Whether the product is active. Only present in responses."
              },
              { 
                name: "name", 
                type: "string", 
                label: "Product Name",
                hint: "The name of the product. Required for creation."
              },
              { 
                name: "description", 
                type: "string", 
                label: "Description",
                hint: "A description of the product. Optional.",
                optional: true 
              },
              { 
                name: "sku", 
                type: "string", 
                label: "SKU",
                hint: "Stock keeping unit. Optional.",
                optional: true 
              },
              { 
                name: "product-id", 
                type: "string", 
                label: "Product ID",
                hint: "External product identifier. Optional.",
                optional: true 
              },
              { 
                name: "manufacturer-part-number", 
                type: "string", 
                label: "Manufacturer Part Number",
                hint: "Manufacturer's part number. Optional.",
                optional: true 
              },
              { 
                name: "unit-of-measure", 
                type: "string", 
                label: "Unit of Measure",
                hint: "Unit used for measuring quantity. Optional.",
                optional: true 
              },
              { 
                name: "unit-cost", 
                type: "number", 
                label: "Unit Cost",
                hint: "Cost per unit. Optional.",
                optional: true 
              },
              { 
                name: "unit-price", 
                type: "number", 
                label: "Unit Price",
                hint: "Price per unit. Optional.",
                optional: true 
              },
              { 
                name: "category", 
                type: "string", 
                label: "Category",
                hint: "Product category. Optional.",
                optional: true 
              },
              { 
                name: "subcategory", 
                type: "string", 
                label: "Subcategory",
                hint: "Product subcategory. Optional.",
                optional: true 
              },
              { 
                name: "list-price", 
                type: "number", 
                label: "List Price",
                hint: "Standard list price. Only present in responses.",
                optional: true 
              },
              { 
                name: "markup", 
                type: "number", 
                label: "Markup",
                hint: "Markup percentage. Only present in responses.",
                optional: true 
              },
              { 
                name: "vendor-discount", 
                type: "number", 
                label: "Vendor Discount",
                hint: "Discount from vendor. Only present in responses.",
                optional: true 
              },
              { 
                name: "vendor-rebate", 
                type: "number", 
                label: "Vendor Rebate",
                hint: "Rebate from vendor. Only present in responses.",
                optional: true 
              },
              { 
                name: "billing-frequency", 
                type: "string", 
                label: "Billing Frequency",
                hint: "Frequency of billing (e.g., 'one_time'). Only present in responses.",
                optional: true 
              },
              { 
                name: "custom-hardware-price?", 
                type: "boolean", 
                label: "Custom Hardware Price",
                hint: "Whether hardware price is custom. Only present in responses.",
                optional: true 
              },
              { 
                name: "custom-hardware-cost?", 
                type: "boolean", 
                label: "Custom Hardware Cost",
                hint: "Whether hardware cost is custom. Only present in responses.",
                optional: true 
              },
              {
                name: "project-variables",
                type: "array",
                label: "Project Variables",
                hint: "Variables associated with the product. Only present in responses.",
                optional: true,
                of: "object",
                properties: [
                  { 
                    name: "name", 
                    type: "string", 
                    label: "Variable Name",
                    hint: "The unique identifier for this variable"
                  },
                  { 
                    name: "label", 
                    type: "string", 
                    label: "Variable Label",
                    hint: "The display name for this variable"
                  },
                  { 
                    name: "variable_type", 
                    type: "string", 
                    label: "Variable Type",
                    hint: "The type of variable (e.g., text, number, select)"
                  },
                  { 
                    name: "minimum", 
                    type: "number", 
                    label: "Minimum Value",
                    hint: "The minimum allowed value for numeric variables",
                    optional: true 
                  },
                  { 
                    name: "maximum", 
                    type: "number", 
                    label: "Maximum Value",
                    hint: "The maximum allowed value for numeric variables",
                    optional: true 
                  },
                  { 
                    name: "required", 
                    type: "boolean", 
                    label: "Required",
                    hint: "Whether this variable must be provided"
                  },
                  {
                    name: "select_options",
                    type: "array",
                    of: "object",
                    label: "Select Options",
                    hint: "Available options for select-type variables",
                    properties: [
                      { 
                        name: "key", 
                        type: "string", 
                        label: "Option Key",
                        hint: "The value to be stored"
                      },
                      { 
                        name: "value", 
                        type: "string", 
                        label: "Option Value",
                        hint: "The display text for this option"
                      },
                      { 
                        name: "default", 
                        type: "boolean", 
                        label: "Default Option",
                        hint: "Whether this option should be selected by default"
                      }
                    ]
                  },
                  { 
                    name: "position", 
                    type: "integer", 
                    label: "Position",
                    hint: "The order in which this variable should be displayed"
                  },
                  { 
                    name: "context", 
                    type: "string", 
                    label: "Context",
                    hint: "The context in which this variable is used (e.g., 'product')"
                  },
                  { 
                    name: "uuid", 
                    type: "string", 
                    label: "UUID",
                    hint: "The unique identifier for this variable instance"
                  },
                  { 
                    name: "value", 
                    type: "string", 
                    label: "Value",
                    hint: "The current value of this variable",
                    optional: true 
                  }
                ]
              },
              {
                name: "variable-rates",
                type: "object",
                label: "Variable Rates",
                hint: "Variable pricing rates. Only present in responses.",
                optional: true,
                properties: [
                  {
                    name: "hardware_cost",
                    type: "array",
                    of: "object",
                    label: "Hardware Cost Rates",
                    properties: [
                      { name: "base_amount", type: "number", label: "Base Amount" },
                      { name: "unit_amount", type: "number", label: "Unit Amount" },
                      { name: "minimum_quantity", type: "integer", label: "Minimum Quantity" }
                    ]
                  },
                  {
                    name: "hardware_price",
                    type: "array",
                    of: "object",
                    label: "Hardware Price Rates",
                    properties: [
                      { name: "base_amount", type: "number", label: "Base Amount" },
                      { name: "unit_amount", type: "number", label: "Unit Amount" },
                      { name: "minimum_quantity", type: "integer", label: "Minimum Quantity" }
                    ]
                  }
                ]
              }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "account",
                type: "object",
                properties: [
                  {
                    name: "data",
                    type: "object",
                    label: "Account Data",
                    hint: "Required for creation. Contains account ID and type.",
                    properties: [
                      { name: "id", type: "integer", label: "Account ID" },
                      { name: "type", type: "string", label: "Account Type" }
                    ]
                  },
                  {
                    name: "links",
                    type: "object",
                    label: "Account Links",
                    hint: "Only present in responses.",
                    optional: true,
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "services",
                type: "object",
                label: "Services",
                hint: "Only present in responses.",
                optional: true,
                properties: [
                  {
                    name: "data",
                    type: "array",
                    of: "object",
                    label: "Service Data",
                    properties: [
                      { name: "id", type: "string", label: "Service ID" },
                      { name: "type", type: "string", label: "Service Type" }
                    ]
                  },
                  {
                    name: "links",
                    type: "object",
                    label: "Service Links",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    project_approval: {
      fields: lambda do |_connection, _config_fields|
      [
        {
          name: 'id',
          label: 'Approval ID',
          type: 'string'
        },
        {
          name: 'type',
          label: 'Type',
          type: 'string'
        },
        {
          name: 'links',
          type: 'object',
          properties: [
            { name: 'self', type: 'string' },
            { name: 'approve', type: 'string', optional: true },
            { name: 'decline', type: 'string', optional: true },
            { name: 'rescope', type: 'string', optional: true },
            { name: 'cancel', type: 'string', optional: true }
          ]
        },
        {
          name: 'attributes',
          type: 'object',
          properties: [
            {
              name: 'status',
              type: 'string',
              control_type: 'select',
              pick_list: [
                ['Optional', 'optional'],
                ['Approved', 'approved'],
                ['Declined', 'declined'],
                ['Rescope', 'rescope']
              ]
            },
            { name: 'role', type: 'string' },
            { name: 'comment', type: 'string', optional: true },
            { name: 'reason', type: 'string' },
            { name: 'completed-at', type: 'timestamp', optional: true },
            { name: 'approver-name', type: 'string' },
            { 
              name: 'lob-ids',
              type: 'array',
              of: 'string'
            }
          ]
        },
        {
          name: 'relationships',
          type: 'object',
          properties: [
            {
              name: 'project',
              type: 'object',
              properties: [
                {
                  name: 'links',
                  type: 'object',
                  properties: [
                    { name: 'self', type: 'string' },
                    { name: 'related', type: 'string' }
                  ]
                }
              ]
            },
            {
              name: 'user',
              type: 'object',
              properties: [
                {
                  name: 'links',
                  type: 'object',
                  properties: [
                    { name: 'self', type: 'string' },
                    { name: 'related', type: 'string' }
                  ]
                }
              ]
            },
            {
              name: 'approval-step',
              type: 'object',
              properties: [
                {
                  name: 'links',
                  type: 'object',
                  properties: [
                    { name: 'self', type: 'string' },
                    { name: 'related', type: 'string' }
                  ]
                }
              ]
            }
          ]
        }
      ]
    end
    },

    user: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'id',
            type: 'string',
            label: 'User ID'
          },
          {
            name: 'type',
            type: 'string'
          },
          {
            name: 'links',
            type: 'object',
            properties: [
              { name: 'self', type: 'string' }
            ]
          },
          {
            name: 'attributes',
            type: 'object',
            properties: [
              { name: 'name', type: 'string' },
              { name: 'email', type: 'string' },
              { name: 'phone', type: 'string', optional: true },
              { name: 'title', type: 'string', optional: true },
              { 
                name: 'privileges',
                type: 'object',
                properties: [
                  { name: 'projects.psa', type: 'string' },
                  { name: 'projects.notes', type: 'string' },
                  { name: 'projects.tasks', type: 'string' },
                  # Add other privileges as needed
                ]
              },
              {
                name: 'preferred-rate-table',
                type: 'object',
                properties: [
                  { name: 'account_id', type: 'integer' },
                  { name: 'name', type: 'string' },
                  { name: 'currency_id', type: 'integer' },
                  { name: 'deleted_at', type: 'string', optional: true },
                  { name: 'default', type: 'boolean' },
                  { name: 'accounting_code', type: 'string', optional: true },
                  { name: 'uuid', type: 'string' }
                ]
              },
              { name: 'guided-onboarding', type: 'object' },
              { name: 'view-only', type: 'boolean' }
            ]
          },
          {
            name: 'relationships',
            type: 'object',
            properties: [
              {
                name: 'account',
                type: 'object',
                properties: [
                  {
                    name: 'links',
                    type: 'object',
                    properties: [
                      { name: 'self', type: 'string' },
                      { name: 'related', type: 'string' }
                    ]
                  }
                ]
              },
              {
                name: 'rate-table',
                type: 'object',
                properties: [
                  {
                    name: 'links',
                    type: 'object',
                    properties: [
                      { name: 'self', type: 'string' },
                      { name: 'related', type: 'string' }
                    ]
                  }
                ]
              },
              {
                name: 'teams',
                type: 'object',
                properties: [
                  {
                    name: 'links',
                    type: 'object',
                    properties: [
                      { name: 'self', type: 'string' },
                      { name: 'related', type: 'string' }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    vendor: {
      fields: lambda do |_connection, _config_fields|
        [
          {
            name: 'id',
            type: 'string',
            label: 'Vendor ID',
            hint: 'The unique identifier of the vendor'
          },
          {
            name: 'type',
            type: 'string',
            label: 'Type',
            hint: 'Always "vendors" for this resource type'
          },
          {
            name: 'links',
            type: 'object',
            label: 'Resource Links',
            hint: 'Links to related resources. Only present in responses.',
            properties: [
              { name: 'self', type: 'string', label: 'Self Link' }
            ]
          },
          {
            name: 'attributes',
            type: 'object',
            properties: [
              { 
                name: 'active', 
                type: 'boolean', 
                label: 'Active',
                hint: 'Whether the vendor is active. Only present in responses.'
              },
              { 
                name: 'name', 
                type: 'string', 
                label: 'Vendor Name',
                hint: 'The name of the vendor. Required for creation.'
              },
              { 
                name: 'street-address', 
                type: 'string', 
                label: 'Street Address',
                hint: 'The street address of the vendor. Optional.',
                optional: true 
              },
              { 
                name: 'street2', 
                type: 'string', 
                label: 'Street Address 2',
                hint: 'Additional street address information. Optional.',
                optional: true 
              },
              { 
                name: 'city', 
                type: 'string', 
                label: 'City',
                hint: 'The city where the vendor is located. Optional.',
                optional: true 
              },
              { 
                name: 'state', 
                type: 'string', 
                label: 'State/Province',
                hint: 'The state or province where the vendor is located. Optional.',
                optional: true 
              },
              { 
                name: 'postal-code', 
                type: 'string', 
                label: 'Postal Code',
                hint: 'The postal code of the vendor. Optional.',
                optional: true 
              },
              { 
                name: 'country', 
                type: 'string', 
                label: 'Country',
                hint: 'The country where the vendor is located. Optional.',
                optional: true 
              },
              { 
                name: 'project-count', 
                type: 'integer', 
                label: 'Project Count',
                hint: 'Number of projects associated with this vendor. Only present in responses.'
              }
            ]
          },
          {
            name: 'relationships',
            type: 'object',
            properties: [
              {
                name: 'account',
                type: 'object',
                properties: [
                  {
                    name: 'data',
                    type: 'object',
                    label: 'Account Data',
                    hint: 'Required for creation. Contains account ID and type.',
                    properties: [
                      { name: 'id', type: 'integer', label: 'Account ID' },
                      { name: 'type', type: 'string', label: 'Account Type' }
                    ]
                  },
                  {
                    name: 'links',
                    type: 'object',
                    label: 'Account Links',
                    hint: 'Only present in responses.',
                    optional: true,
                    properties: [
                      { name: 'self', type: 'string', label: 'Self Link' },
                      { name: 'related', type: 'string', label: 'Related Link' }
                    ]
                  }
                ]
              },
              {
                name: 'quotes',
                type: 'object',
                properties: [
                  {
                    name: 'links',
                    type: 'object',
                    label: 'Quotes Links',
                    hint: 'Only present in responses.',
                    optional: true,
                    properties: [
                      { name: 'self', type: 'string', label: 'Self Link' },
                      { name: 'related', type: 'string', label: 'Related Link' }
                    ]
                  },
                  {
                    name: 'data',
                    type: 'array',
                    of: 'object',
                    label: 'Quotes Data',
                    hint: 'Only present in responses.',
                    optional: true,
                    properties: [
                      { name: 'id', type: 'integer', label: 'Quote ID' },
                      { name: 'type', type: 'string', label: 'Quote Type' }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    project_governance: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Project Governance ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "links",
            type: "object",
            properties: [
              { name: "allocation-methods", type: "string", label: "Allocation Methods Link" },
              { name: "calculation-types", type: "string", label: "Calculation Types Link" },
              { name: "self", type: "string", label: "Self Link" }
            ]
          },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "active", type: "boolean", label: "Active" },
              { name: "description", type: "string", label: "Description" },
              { name: "rate", type: "string", label: "Rate" },
              { name: "fixed-hours", type: "string", label: "Fixed Hours" },
              { name: "calculation-type", type: "string", label: "Calculation Type" },
              { name: "allocation-method", type: "string", label: "Allocation Method" },
              { name: "hours", type: "string", label: "Hours" },
              { name: "fixed_hours_in_minutes", type: "integer", label: "Fixed Hours (in minutes)", optional: true },
              { name: "hours_in_minutes", type: "integer", label: "Hours (in minutes)", optional: true },
              { name: "assign-effort-to-service", type: "boolean", label: "Assign Effort to Service" },
              { name: "filter-type", type: "string", label: "Filter Type" },
              { name: "filter-id", type: "string", label: "Filter ID" },
              { name: "position", type: "integer", label: "Position" },
              {
                name: "project-variables",
                type: "array",
                of: "object",
                properties: [
                  { name: "name", type: "string", label: "Name" },
                  { name: "label", type: "string", label: "Label" },
                  { name: "variable_type", type: "string", label: "Variable Type" },
                  { name: "minimum", type: "integer", label: "Minimum" },
                  { name: "maximum", type: "integer", label: "Maximum" },
                  { name: "required", type: "boolean", label: "Required" },
                  {
                    name: "select_options",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "key", type: "string", label: "Key" },
                      { name: "value", type: "string", label: "Value" },
                      { name: "default", type: "boolean", label: "Default" }
                    ]
                  },
                  { name: "position", type: "integer", label: "Position" },
                  { name: "context", type: "string", label: "Context" },
                  { name: "uuid", type: "string", label: "UUID" },
                  { name: "value", type: "string", label: "Value" }
                ]
              }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "project",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    optional: true,
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "ID" }
                    ]
                  }
                ]
              },
              {
                name: "project-phase",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    optional: true,
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "ID" }
                    ]
                  }
                ]
              },
              {
                name: "governance",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    optional: true,
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "ID" }
                    ]
                  }
                ]
              },
              {
                name: "project-resource",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    optional: true,
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "ID" }
                    ]
                  }
                ]
              },
              {
                name: "resource",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    optional: true,
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "ID" }
                    ]
                  }
                ]
              },
              {
                name: "resource-rate",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    optional: true,
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "ID" }
                    ]
                  }
                ]
              },
              {
                name: "service-category",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    optional: true,
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "ID" }
                    ]
                  }
                ]
              }
            ]
          },
          {
            name: "meta",
            type: "object",
            properties: [
              {
                name: "permissions",
                type: "object",
                properties: [
                  { name: "view", type: "boolean", label: "View Permission" },
                  { name: "create", type: "boolean", label: "Create Permission" },
                  { name: "manage", type: "boolean", label: "Manage Permission" }
                ]
              }
            ]
          }
        ]
      end
    },

    governance: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Governance ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "links",
            type: "object",
            properties: [
              { name: "self", type: "string", label: "Self Link" }
            ]
          },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "active", type: "boolean", label: "Active" },
              { name: "name", type: "string", label: "Name" },
              { name: "rate", type: "string", label: "Rate" },
              { name: "fixed-hours", type: "string", label: "Fixed Hours" },
              { name: "calculation-type", type: "string", label: "Calculation Type" },
              { name: "allocation-method", type: "string", label: "Allocation Method" },
              { name: "rate_in_cents", type: "integer", label: "Rate (in cents)", optional: true },
              { name: "fixed_hours_in_minutes", type: "integer", label: "Fixed Hours (in minutes)", optional: true },
              { name: "required", type: "boolean", label: "Required" },
              { name: "assign-effort-to-service", type: "boolean", label: "Assign Effort to Service" },
              { name: "filter-type", type: "string", label: "Filter Type" },
              { name: "filter-id", type: "string", label: "Filter ID" },
              { name: "position", type: "integer", label: "Position" }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "account",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "resource",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "phase",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "service-category",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    project_phase: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Project Phase ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "links",
            type: "object",
            properties: [
              { name: "self", type: "string", label: "Self Link" }
            ]
          },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "active", type: "boolean", label: "Active" },
              { name: "name", type: "string", label: "Name" },
              { name: "sow-language", type: "string", label: "SOW Language" },
              { name: "position", type: "integer", label: "Position" }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "project",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "phase",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    project_service: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Project Service ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "links",
            type: "object",
            properties: [
              { name: "synchronize-standard", type: "string", label: "Synchronize Standard Link" },
              { name: "self", type: "string", label: "Self Link" }
            ]
          },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "active", type: "boolean", label: "Active" },
              { name: "name", type: "string", label: "Name" },
              { name: "quantity", type: "integer", label: "Quantity" },
              { name: "override-hours", type: "string", label: "Override Hours" },
              { name: "actual-hours", type: "string", label: "Actual Hours" },
              { name: "override_hours_in_minutes", type: "integer", label: "Override Hours (in minutes)", optional: true },
              { name: "actual_hours_in_minutes", type: "integer", label: "Actual Hours (in minutes)", optional: true },
              { name: "position", type: "integer", label: "Position" },
              { name: "service-type", type: "string", label: "Service Type" },
              { name: "lob-id", type: "integer", label: "LOB ID" },
              { name: "payment-frequency", type: "string", label: "Payment Frequency" },
              { name: "task-source", type: "string", label: "Task Source" },
              {
                name: "languages",
                type: "object",
                properties: [
                  { name: "out", type: "string", label: "Out of Scope Language" },
                  { name: "customer", type: "string", label: "Customer Language" },
                  { name: "assumptions", type: "string", label: "Assumptions Language" },
                  { name: "deliverables", type: "string", label: "Deliverables Language" },
                  { name: "sow_language", type: "string", label: "SOW Language" },
                  { name: "design_language", type: "string", label: "Design Language" },
                  { name: "planning_language", type: "string", label: "Planning Language" },
                  { name: "implementation_language", type: "string", label: "Implementation Language" }
                ]
              },
              {
                name: "variable-rates",
                type: "object",
                properties: [
                  {
                    name: "hours",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "base_amount", type: "string", label: "Base Amount" },
                      { name: "unit_amount", type: "string", label: "Unit Amount" },
                      { name: "minimum_quantity", type: "string", label: "Minimum Quantity" }
                    ]
                  }
                ]
              },
              {
                name: "calculated-pricing",
                type: "object",
                properties: [
                  { name: "service_cost", type: "string", label: "Service Cost" },
                  { name: "material_cost", type: "integer", label: "Material Cost" },
                  { name: "extended_hours", type: "string", label: "Extended Hours" },
                  { name: "service_revenue", type: "string", label: "Service Revenue" },
                  { name: "material_revenue", type: "integer", label: "Material Revenue" },
                  { name: "service_cost_in_cents", type: "integer", label: "Service Cost (in cents)", optional: true },
                  { name: "extended_hours_in_minutes", type: "integer", label: "Extended Hours (in minutes)", optional: true },
                  { name: "service_revenue_in_cents", type: "integer", label: "Service Revenue (in cents)", optional: true }
                ]
              },
              { name: "extended-hours", type: "string", label: "Extended Hours" },
              { name: "total-hours", type: "string", label: "Total Hours" },
              { name: "extended_hours_in_minutes", type: "integer", label: "Extended Hours (in minutes)", optional: true },
              { name: "total_hours_in_minutes", type: "integer", label: "Total Hours (in minutes)", optional: true },
              { name: "external-resource-name", type: "string", label: "External Resource Name" },
              { name: "sku", type: "string", label: "SKU" },
              { name: "service-description", type: "string", label: "Service Description" },
              { name: "target-margin", type: "string", label: "Target Margin" },
              { name: "payment-method", type: "string", label: "Payment Method" },
              { name: "resource-rate-id", type: "string", label: "Resource Rate ID" },
              { name: "custom-hours?", type: "string", label: "Custom Hours" },
              { name: "notes", type: "array", of: "string", label: "Notes" }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "project",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project-location",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project-phase",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "integer", label: "ID" }
                    ]
                  }
                ]
              },
              {
                name: "project-resource",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "resource",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "service",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "lob",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "service-category",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project-subservices",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    project_subservice: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Project Subservice ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "links",
            type: "object",
            properties: [
              { name: "synchronize-standard", type: "string", label: "Synchronize Standard Link" },
              { name: "self", type: "string", label: "Self Link" }
            ]
          },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "active", type: "boolean", label: "Active" },
              { name: "name", type: "string", label: "Name" },
              { name: "quantity", type: "integer", label: "Quantity" },
              { name: "extended-hours", type: "string", label: "Extended Hours" },
              { name: "override-hours", type: "string", label: "Override Hours" },
              { name: "actual-hours", type: "string", label: "Actual Hours", optional: true },
              { name: "extended_hours_in_minutes", type: "integer", label: "Extended Hours (in minutes)", optional: true },
              { name: "override_hours_in_minutes", type: "integer", label: "Override Hours (in minutes)", optional: true },
              { name: "actual_hours_in_minutes", type: "integer", label: "Actual Hours (in minutes)", optional: true },
              { name: "position", type: "integer", label: "Position" },
              { name: "service-type", type: "string", label: "Service Type" },
              { name: "payment-frequency", type: "string", label: "Payment Frequency" },
              { name: "task-source", type: "string", label: "Task Source" },
              {
                name: "languages",
                type: "object",
                properties: [
                  { name: "out", type: "string", label: "Out of Scope Language" },
                  { name: "customer", type: "string", label: "Customer Language" },
                  { name: "assumptions", type: "string", label: "Assumptions Language" },
                  { name: "deliverables", type: "string", label: "Deliverables Language" },
                  { name: "sow_language", type: "string", label: "SOW Language" },
                  { name: "design_language", type: "string", label: "Design Language" },
                  { name: "planning_language", type: "string", label: "Planning Language" },
                  { name: "implementation_language", type: "string", label: "Implementation Language" }
                ]
              },
              {
                name: "variable-rates",
                type: "object",
                properties: [
                  {
                    name: "hours",
                    type: "array",
                    of: "object",
                    properties: [
                      { name: "base_amount", type: "string", label: "Base Amount" },
                      { name: "unit_amount", type: "string", label: "Unit Amount" },
                      { name: "minimum_quantity", type: "string", label: "Minimum Quantity" }
                    ]
                  }
                ]
              },
              {
                name: "calculated-pricing",
                type: "object",
                properties: [
                  { name: "service_cost", type: "string", label: "Service Cost" },
                  { name: "material_cost", type: "integer", label: "Material Cost" },
                  { name: "extended_hours", type: "string", label: "Extended Hours" },
                  { name: "service_revenue", type: "string", label: "Service Revenue" },
                  { name: "material_revenue", type: "integer", label: "Material Revenue" },
                  { name: "service_cost_in_cents", type: "integer", label: "Service Cost (in cents)", optional: true },
                  { name: "extended_hours_in_minutes", type: "integer", label: "Extended Hours (in minutes)", optional: true },
                  { name: "service_revenue_in_cents", type: "integer", label: "Service Revenue (in cents)", optional: true }
                ]
              },
              { name: "external-resource-name", type: "string", label: "External Resource Name", optional: true },
              { name: "sku", type: "string", label: "SKU", optional: true },
              { name: "service-description", type: "string", label: "Service Description" },
              { name: "payment-method", type: "string", label: "Payment Method" },
              { name: "resource-rate-id", type: "string", label: "Resource Rate ID", optional: true },
              { name: "custom-hours?", type: "string", label: "Custom Hours", optional: true }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "account",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project-service",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project-location",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "lob",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "phase",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project-resource",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "resource",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "service-category",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "subservice",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    project_resource: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Project Resource ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "links",
            type: "object",
            properties: [
              { name: "self", type: "string", label: "Self Link" }
            ]
          },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "active", type: "boolean", label: "Active" },
              { name: "name", type: "string", label: "Name" },
              { name: "external-name", type: "string", label: "External Name", optional: true },
              { name: "extended-name", type: "string", label: "Extended Name" },
              { name: "description", type: "string", label: "Description", optional: true },
              { name: "total-hours", type: "string", label: "Total Hours" },
              { name: "hourly-rate", type: "string", label: "Hourly Rate" },
              { name: "hourly-cost", type: "string", label: "Hourly Cost" },
              { name: "expense-rate", type: "string", label: "Expense Rate" },
              { name: "total_hours_in_minutes", type: "integer", label: "Total Hours (in minutes)", optional: true },
              { name: "hourly_rate_in_cents", type: "integer", label: "Hourly Rate (in cents)", optional: true },
              { name: "hourly_cost_in_cents", type: "integer", label: "Hourly Cost (in cents)", optional: true },
              { name: "expense_rate_in_cents", type: "integer", label: "Expense Rate (in cents)", optional: true },
              { name: "code", type: "string", label: "Code", optional: true },
              {
                name: "resource",
                type: "object",
                label: "Resource",
                properties: [
                  { name: "resource_type", type: "string", label: "Resource Type" },
                  { name: "resource_id", type: "integer", label: "Resource ID" },
                  { name: "name", type: "string", label: "Name" },
                  { name: "hourly_rate", type: "string", label: "Hourly Rate" },
                  { name: "account_id", type: "integer", label: "Account ID" },
                  { name: "hourly_cost", type: "string", label: "Hourly Cost" },
                  { name: "hourly_rate_in_cents", type: "integer", label: "Hourly Rate (in cents)", optional: true },
                  { name: "hourly_cost_in_cents", type: "integer", label: "Hourly Cost (in cents)", optional: true },
                  { name: "status", type: "integer", label: "Status" },
                  { name: "deleted_at", type: "string", label: "Deleted At", optional: true },
                  { name: "external_name", type: "string", label: "External Name", optional: true },
                  { name: "description", type: "string", label: "Description", optional: true },
                  { name: "default", type: "boolean", label: "Default" }
                ]
              }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "project",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    optional: true,
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "Project ID" }
                    ]
                  }
                ]
              },
              {
                name: "resource",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "line-of-business",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    resource: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: "id", type: "integer", label: "Resource ID" },
          { name: "type", type: "string", label: "Type" },
          {
            name: "links",
            type: "object",
            properties: [
              { name: "self", type: "string", label: "Self Link" }
            ]
          },
          {
            name: "attributes",
            type: "object",
            properties: [
              { name: "active", type: "boolean", label: "Active" },
              { name: "name", type: "string", label: "Name" },
              { name: "external-name", type: "string", label: "External Name", optional: true },
              { name: "description", type: "string", label: "Description", optional: true },
              { name: "hourly-rate", type: "string", label: "Hourly Rate" },
              { name: "hourly-cost", type: "string", label: "Hourly Cost" },
              { name: "hourly_rate_in_cents", type: "integer", label: "Hourly Rate (in cents)", optional: true },
              { name: "hourly_cost_in_cents", type: "integer", label: "Hourly Cost (in cents)", optional: true }
            ]
          },
          {
            name: "relationships",
            type: "object",
            properties: [
              {
                name: "account",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "object",
                    optional: true,
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "Account ID" }
                    ]
                  }
                ]
              },
              {
                name: "governances",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  },
                  {
                    name: "data",
                    type: "array",
                    optional: true,
                    of: "object",
                    properties: [
                      { name: "type", type: "string", label: "Type" },
                      { name: "id", type: "string", label: "Governance ID" }
                    ]
                  }
                ]
              },
              {
                name: "project-governances",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project-resources",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project-services",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              },
              {
                name: "project-subservices",
                type: "object",
                properties: [
                  {
                    name: "links",
                    type: "object",
                    properties: [
                      { name: "self", type: "string", label: "Self Link" },
                      { name: "related", type: "string", label: "Related Link" }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    }

  },

  # This implements a standard custom action for your users to unblock themselves even when no actions exist.
  # See more at https://docs.workato.com/developing-connectors/sdk/guides/building-actions/custom-action.html
  custom_action: true,

  custom_action_help: {
    learn_more_url: "https://api.scopestack.io/docs",
    learn_more_text: "ScopeStack documentation",
    body: "<p>Build your own ScopeStack actions with a HTTP request. The request will be authorized with your ScopeStack connection.</p>"
  },

  triggers: {
    updated_projects: {
      title: "Updated Projects",
      subtitle: "Get projects that have been updated",
      description: "Get projects that have been updated since the last poll",
      help: "This trigger polls for projects that have been updated since the specified time. On first run, it will use the provided 'since' time. On subsequent runs, it will use the last successful poll time.",
      
      input_fields: lambda do |_object_definitions|
        [
          {
            name: "since",
            label: "When first started, this recipe should pick up events from",
            type: "timestamp",
            optional: false,
            sticky: true,
            hint: "When you start recipe for the first time, it picks up projects from this specified date and time. The API filters by day, so any projects updated on or after this date will be included. Defaults to yesterday to ensure no updates are missed."
          }
        ]
      end,

      poll: lambda do |connection, input, closure|
        puts "=== STARTING UPDATED PROJECTS POLL ==="
        puts "Input: #{input.inspect}"
        puts "Initial closure: #{closure.inspect}"
        puts "Connection keys: #{connection.keys if connection.is_a?(Hash)}"
        
        # Initialize closure if it doesn't exist
        closure = closure || {}
        puts "Closure after initialization: #{closure.inspect}"
        
        # Get account information using the reusable method
        puts "Calling get_account_info..."
        account_info = call('get_account_info', connection)
        puts "Account info response: #{account_info.inspect}"
        account_slug = account_info[:account_slug]
        
        puts "Account slug: #{account_slug}"
        
        # Get the last poll time from closure or input
        # Convert to date format since API only supports per-day filtering
        puts "Determining last poll date..."
        puts "  closure['last_poll_date']: #{closure['last_poll_date']}"
        puts "  input['since']: #{input['since']}"
        
        last_poll_date = if closure['last_poll_date']
          puts "  Using closure last_poll_date: #{closure['last_poll_date']}"
          closure['last_poll_date']
        elsif input['since']
          formatted_date = input['since'].to_time.strftime('%Y-%m-%d')
          puts "  Using input since date, formatted: #{formatted_date}"
          formatted_date
        else
          default_date = (Time.now - 1.day).strftime('%Y-%m-%d')
          puts "  Using default date (yesterday): #{default_date}"
          default_date
        end
        
        puts "Final last_poll_date: #{last_poll_date}"
        
        begin
          puts "=== MAKING API REQUEST ==="
          puts "URL: /#{account_slug}/v1/projects"
          puts "Filter: filter[updated-at.after]=#{last_poll_date}"
          puts "Expected URL format: /#{account_slug}/v1/projects?filter[updated-at.after]=#{last_poll_date}&include=..."
          
          # No includes for now to keep it simple
          includes = []
          
          # Try different parameter formats to see which one works
          # Let's try multiple filter formats to see if any work
          params = { 
            'filter[updated-at.after]' => last_poll_date,
            'include' => includes.join(',')
          }
          puts "Request params: #{params.inspect}"
          
          # Try using the same approach as the search projects action
          response = get("/#{account_slug}/v1/projects")
                        .headers('Accept': 'application/vnd.api+json')
                        .params(params)
          
          puts "=== REQUEST DEBUG INFO ==="
          puts "Base URL: https://api.scopestack.io"
          puts "Path: /#{account_slug}/v1/projects"
          puts "Filter parameter: filter[updated-at.after]=#{last_poll_date}"
          puts "Full expected URL: https://api.scopestack.io/#{account_slug}/v1/projects?filter[updated-at.after]=#{last_poll_date}&include=#{includes.join(',')}"
          
          puts "=== API RESPONSE RECEIVED ==="
          puts "Response class: #{response.class}"
          puts "Response keys: #{response.keys if response.is_a?(Hash)}"
          puts "Response meta: #{response['meta'] if response.is_a?(Hash)}"
          puts "Response links: #{response['links'] if response.is_a?(Hash)}"
          
          projects = response['data'] || []
          puts "Projects array size: #{projects.size}"
          
          if projects.size > 0
            puts "First project sample (truncated):"
            first_project = projects.first
            puts "  ID: #{first_project['id']}"
            puts "  Type: #{first_project['type']}"
            puts "  Updated at: #{first_project.dig('attributes', 'updated-at')}"
            puts "  Project name: #{first_project.dig('attributes', 'project-name')}"
            puts "  Status: #{first_project.dig('attributes', 'status')}"
            puts "  Created at: #{first_project.dig('attributes', 'created-at')}"
            
            # Show a few more projects to see the date range
            puts "Sample of project dates:"
            projects.first(5).each do |project|
              puts "  Project #{project['id']}: #{project.dig('attributes', 'updated-at')} (#{project.dig('attributes', 'project-name')})"
            end
            
            # Show the date range of all projects
            if projects.size > 5
              puts "Date range of all projects:"
              dates = projects.map { |p| p.dig('attributes', 'updated-at') }.compact.sort
              puts "  Earliest: #{dates.first}"
              puts "  Latest: #{dates.last}"
              puts "  Total unique dates: #{dates.uniq.size}"
            end
          end
          
          # Since API only filters by day, we need to filter out projects that were already processed
          # by checking if we've seen them before with the same updated_at timestamp
          processed_projects = closure['processed_projects'] || {}
          puts "Processed projects count: #{processed_projects.size}"
          puts "Processed projects keys: #{processed_projects.keys.first(5)}" if processed_projects.size > 0
          
          puts "=== FILTERING PROJECTS ==="
          puts "Filtering by date: #{last_poll_date}"
          puts "Converting last_poll_date to Time object for comparison..."
          filter_date = Date.parse(last_poll_date).to_time
          puts "Filter date (Time): #{filter_date}"
          
          updated_projects = projects.select do |project|
            begin
              project_id = project['id']
              updated_at = project.dig('attributes', 'updated-at')
              puts "  Checking project #{project_id}: updated_at=#{updated_at}"
              
              next false unless updated_at
              
              # Parse the updated_at timestamp
              project_updated_time = Time.parse(updated_at)
              puts "    Project updated time: #{project_updated_time}"
              puts "    Filter date: #{filter_date}"
              puts "    Is after filter date? #{project_updated_time > filter_date}"
              
              # Manual date filtering since API filter doesn't seem to work
              unless project_updated_time > filter_date
                puts "    -> Project updated before filter date, skipping"
                next false
              end
              
              # Check if we've already processed this project with this exact timestamp
              if processed_projects[project_id] == updated_at
                puts "    -> Already processed with same timestamp, skipping"
                next false
              end
              
              puts "    -> New or updated project, including"
              true
            rescue => e
              puts "    -> Error processing project #{project['id']}: #{e.message}"
              false
            end
          end
          
          puts "Found #{updated_projects.size} new/updated projects"
          
          # Update processed projects tracking
          puts "=== UPDATING PROCESSED PROJECTS TRACKING ==="
          updated_projects.each do |project|
            project_id = project['id']
            updated_at = project.dig('attributes', 'updated-at')
            processed_projects[project_id] = updated_at
            puts "  Marked project #{project_id} as processed with timestamp #{updated_at}"
          end
          
          # Clean up old processed projects (keep only last 1000 to prevent memory issues)
          if processed_projects.size > 1000
            puts "Cleaning up processed projects cache (was #{processed_projects.size})"
            # Keep only the most recent 500 entries
            processed_projects = processed_projects.to_a.last(500).to_h
            puts "After cleanup: #{processed_projects.size} entries"
          end
          
          # Format each project into an event
          puts "=== FORMATTING EVENTS ==="
          events = updated_projects.map do |project|
            event = {
              id: project['id'],
              updated_at: project.dig('attributes', 'updated-at'),
              data: project
            }
            puts "  Created event for project #{project['id']}"
            event
          end
          
          # Update closure with current date and processed projects
          current_date = Time.now.strftime('%Y-%m-%d')
          next_closure = {
            'last_poll_date': current_date,
            'processed_projects': processed_projects
          }
          
          puts "=== RETURNING RESPONSE ==="
          puts "Events count: #{events.size}"
          puts "Next closure last_poll_date: #{next_closure['last_poll_date']}"
          puts "Next closure processed_projects count: #{next_closure['processed_projects']&.size || 0}"
          puts "Updated closure: #{next_closure.inspect}"
          
          result = {
            events: events,
            next_poll: next_closure,
            can_poll_more: false
          }
          
          puts "Final result: #{result.inspect}"
          puts "=== POLL COMPLETED ==="
          
          result
        rescue => e
          puts "=== ERROR IN POLL ==="
          puts "Error class: #{e.class}"
          puts "Error message: #{e.message}"
          puts "Error backtrace:"
          puts e.backtrace.first(10).join("\n")
          error("Polling failed: #{e.message}")
        end
      end,

      dedup: lambda do |project|
        # The project parameter here is the event we created, not the original project data
        project_id = project['id']
        updated_at = project['updated_at']
        puts "Dedup - Project ID: #{project_id}, Updated at: #{updated_at}"
        dedup_key = "#{project_id}@#{updated_at}"
        puts "Generated dedup key for project #{project_id}: #{dedup_key}"
        dedup_key
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['project']
      end
    },

    project_crm_opportunity_changes: {
      title: "Project CRM Opportunity Changes",
      subtitle: "Get projects when their CRM opportunity relationship changes",
      description: "Get projects when their linked CRM opportunity is added, updated, or removed",
      help: "This trigger polls for projects and detects changes in their CRM opportunity relationships. It will trigger when a project gets a new CRM opportunity, has its CRM opportunity changed, or has its CRM opportunity removed.",
      
      input_fields: lambda do |_object_definitions|
        [
          {
            name: "since",
            label: "When first started, this recipe should pick up events from",
            type: "timestamp",
            optional: false,
            sticky: true,
            hint: "When you start recipe for the first time, it picks up projects from this specified date and time. Defaults to the current time."
          },
          {
            name: "includes",
            label: "Include Related Data",
            type: "object",
            properties: [
              {
                name: 'include_project_details',
                label: 'Project Details',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include full project details including name, client, etc.'
              },
              {
                name: 'include_crm_opportunity_details',
                label: 'CRM Opportunity Details',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include full CRM opportunity details including name, amount, etc.'
              }
            ]
          }
        ]
      end,

      poll: lambda do |connection, input, closure|
        puts "Starting poll with input: #{input.inspect}"
        puts "Initial closure state: #{closure.inspect}"
        
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        puts "Account slug: #{account_slug}"
        
        # Initialize closure if it doesn't exist
        closure = closure || {}
        
        # Get the last poll time from closure or input
        last_poll_time = (closure['last_poll_time'] || input['since']).to_time.utc.iso8601
        current_time = Time.now.utc.iso8601
        
        puts "Polling window: #{last_poll_time} to #{current_time}"
        
        begin
          puts "Making API request to /#{account_slug}/v1/projects"
          
          # Make initial API request to get updated projects
          puts "Requesting projects updated between #{last_poll_time} and #{current_time}"
          response = get("/#{account_slug}/v1/projects", 
                        headers: { 
                          'Accept': 'application/vnd.api+json'
                        },
                        params: { 
                          'filter[updated-at][after]': last_poll_time,
                          'filter[updated-at][before]': current_time
                        })

          # Log response details without trying to access headers
          puts "First project updated_at: #{response.dig('data', 0, 'attributes', 'updated-at')}"
          puts "Filter criteria: after=#{last_poll_time}, before=#{current_time}"

          projects = response['data'] || []
          puts "Found #{projects.size} projects, filtering to ones actually updated in window"

          # Additional filter in code since API seems to ignore date filter
          projects = projects.uniq { |p| p['id'] }.select do |project|
            updated_at = Time.parse(project.dig('attributes', 'updated-at'))
            in_window = updated_at >= Time.parse(last_poll_time) && 
                        updated_at <= Time.parse(current_time)
            puts "Project #{project['id']} updated at #{updated_at} - #{in_window ? 'in window' : 'outside window'}"
            in_window
          end

          puts "After date filtering: #{projects.size} projects"
          
          # Process updated projects
          events = projects.map do |project|
            project_id = project['id']
            puts "\nProcessing project #{project_id}"
            
            # Check if project has CRM opportunity relationship link
            crm_opportunity_link = project.dig('relationships', 'crm-opportunity', 'links', 'related')
            
            if crm_opportunity_link
              puts "  Found CRM opportunity link, fetching details"
              
              begin
                opportunity_response = get(crm_opportunity_link, 
                                         headers: { 'Accept': 'application/vnd.api+json' })
                
                current_opportunity = opportunity_response['data']
                previous_opportunity = closure[project_id]
                
                # If user requested full project details, fetch them
                if input.dig('includes', 'include_project_details')
                  project_response = get("/#{account_slug}/v1/projects/#{project_id}",
                                       headers: { 'Accept': 'application/vnd.api+json' })
                  project = project_response['data']
                end
                
                # If user requested full CRM opportunity details, fetch them
                if input.dig('includes', 'include_crm_opportunity_details') && current_opportunity
                  opportunity_response = get("/#{account_slug}/v1/crm-opportunities/#{current_opportunity['id']}",
                                           headers: { 'Accept': 'application/vnd.api+json' })
                  current_opportunity = opportunity_response['data']
                end
                
                puts "  Current opportunity: #{current_opportunity&.dig('id')}"
                puts "  Previous opportunity: #{previous_opportunity&.dig('id')}"
                
                # For initial run (no previous state), treat existing opportunities as 'added'
                is_initial_run = closure.empty? || closure.keys == ['last_poll_time']
                
                # Determine change type
                change_type = if is_initial_run && current_opportunity
                               puts "    Initial run with opportunity - marking as 'added'"
                               'added'
                             elsif !previous_opportunity && current_opportunity
                               puts "    New opportunity found - marking as 'added'"
                               'added'
                             elsif previous_opportunity && !current_opportunity
                               puts "    Opportunity removed - marking as 'deleted'"
                               'deleted'
                             elsif previous_opportunity && current_opportunity && 
                                   previous_opportunity['id'] != current_opportunity['id']
                               puts "    Opportunity changed - marking as 'updated'"
                               'updated'
                             else
                               puts "    No change detected"
                               nil
                             end
                
                # Only create event if there was a change
                if change_type
                  puts "  Creating event for change type: #{change_type}"
                  {
                    project_id: project_id,
                    project: project,
                    updated_at: project.dig('attributes', 'updated-at'),
                    change_type: change_type,
                    previous_opportunity: previous_opportunity,
                    current_opportunity: current_opportunity
                  }
                end
              rescue => e
                puts "  Error fetching CRM opportunity: #{e.message}"
                nil
              end
            else
              puts "  No CRM opportunity link found"
              nil
            end
          end.compact
          
          # Update closure with current state and time
          new_state = projects.each_with_object({}) do |project, state|
            if project.dig('relationships', 'crm-opportunity', 'links', 'related')
              begin
                opportunity_response = get(project.dig('relationships', 'crm-opportunity', 'links', 'related'),
                                      headers: { 'Accept': 'application/vnd.api+json' })
                state[project['id']] = opportunity_response['data']
              rescue => e
                puts "Error updating closure state for project #{project['id']}: #{e.message}"
              end
            end
          end
          new_state['last_poll_time'] = current_time
          
          puts "\nFound #{events.size} relationship changes"
          
          {
            events: events,
            next_poll: new_state,
            can_poll_more: false
          }
        rescue => e
          puts "Error in poll: #{e.class} - #{e.message}"
          puts "Backtrace: #{e.backtrace.first(5).join("\n")}"
          error("Polling failed: #{e.message}")
        end
      end,

      dedup: lambda do |record|
        "#{record['project_id']}@#{record['updated_at']}@#{record['change_type']}"
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: 'project_id',
            type: 'string',
            label: 'Project ID'
          },
          {
            name: 'project',
            type: 'object',
            properties: [
              {
                name: 'id',
                type: 'string'
              },
              {
                name: 'type',
                type: 'string'
              },
              {
                name: 'attributes',
                type: 'object',
                properties: [
                  {
                    name: 'name',
                    type: 'string',
                    label: 'Project Name'
                  },
                  {
                    name: 'client-name',
                    type: 'string',
                    label: 'Client Name'
                  },
                  {
                    name: 'updated-at',
                    type: 'timestamp',
                    label: 'Updated At'
                  }
                ]
              }
            ]
          },
          {
            name: 'updated_at',
            type: 'timestamp'
          },
          {
            name: 'change_type',
            type: 'string',
            control_type: 'select',
            pick_list: [
              ['Added', 'added'],
              ['Updated', 'updated'],
              ['Deleted', 'deleted']
            ]
          },
          {
            name: 'previous_opportunity',
            type: 'object',
            properties: [
              {
                name: 'id',
                type: 'string'
              },
              {
                name: 'type',
                type: 'string'
              },
              {
                name: 'attributes',
                type: 'object',
                properties: [
                  {
                    name: 'opportunity-id',
                    type: 'string',
                    label: 'CRM Opportunity ID'
                  },
                  {
                    name: 'name',
                    type: 'string',
                    label: 'Opportunity Name'
                  },
                  {
                    name: 'amount',
                    type: 'number',
                    label: 'Amount'
                  },
                  {
                    name: 'stage',
                    type: 'string',
                    label: 'Stage'
                  }
                ]
              }
            ]
          },
          {
            name: 'current_opportunity',
            type: 'object',
            properties: [
              {
                name: 'id',
                type: 'string'
              },
              {
                name: 'type',
                type: 'string'
              },
              {
                name: 'attributes',
                type: 'object',
                properties: [
                  {
                    name: 'opportunity-id',
                    type: 'string',
                    label: 'CRM Opportunity ID'
                  },
                  {
                    name: 'name',
                    type: 'string',
                    label: 'Opportunity Name'
                  },
                  {
                    name: 'amount',
                    type: 'number',
                    label: 'Amount'
                  },
                  {
                    name: 'stage',
                    type: 'string',
                    label: 'Stage'
                  }
                ]
              }
            ]
          }
        ]
      end
    },

    project_approval_notifications: {
      title: 'New Project Approval',
      subtitle: 'Triggers when a new project approval is created',
      description: 'Get notifications when project approvals are created',
      help: 'This trigger polls for new project approvals and includes the full associated project object.',
    
      poll: lambda do |connection, input, closure|
        page_size = 100
        closure ||= {}
        current_page = closure['current_page'] || 1
    
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        puts "Polling project approvals for page #{current_page}"
    
        begin
          response = get("/#{account_slug}/v1/project-approvals",
            headers: { 'Accept': 'application/vnd.api+json' },
            params: {
              page: {
                number: current_page,
                size: page_size
              }
            })
    
          approvals = response['data'] || []
          puts "Processing #{approvals.length} approvals"
    
          events = approvals.map do |approval|
            approval_id = approval['id']
            puts "\nProcessing approval #{approval_id}"
    
            # Get project data using the related link
            project_data = {}
            if project_url = approval.dig('relationships', 'project', 'links', 'related')
              begin
                includes = [
                  'client',
                  'sales-executive',
                  'presales-engineer',
                  'business-unit',
                  'project-phases',
                  'project-products',
                  'project-services'
                ]
                
                project_response = get(project_url, 
                  headers: { 'Accept': 'application/vnd.api+json' },
                  params: {
                    include: includes.join(',')
                  }
                ).after_error_response(/.*/) do |_code, body, _header, message|
                  error("#{message}: #{body}")
                end
                
                if project_response && project_response['data']
                  project_data = project_response['data']
                  puts "Successfully fetched project data"
                end
              rescue => e
                puts "Error fetching project data: #{e.message}"
              end
            end
    
            # Get user data using the related link
            user_info = {}
            user_email = nil
            if user_url = approval.dig('relationships', 'user', 'links', 'related')
              begin
                user_response = get(user_url, 
                  headers: { 'Accept': 'application/vnd.api+json' }
                ).after_error_response(/.*/) do |_code, body, _header, message|
                  error("#{message}: #{body}")
                end
                
                if user_response && user_response['data']
                  user_info = user_response['data']
                  user_email = user_info.dig('attributes', 'email')
                  puts "Successfully fetched user data"
                end
              rescue => e
                puts "Error fetching user data: #{e.message}"
              end
            end
    
            {
              id: approval_id,
              type: approval['type'],
              status: approval.dig('attributes', 'status'),
              role: approval.dig('attributes', 'role'),
              comment: approval.dig('attributes', 'comment'),
              reason: approval.dig('attributes', 'reason'),
              completed_at: approval.dig('attributes', 'completed-at'),
              approver_name: approval.dig('attributes', 'approver-name'),
              lob_ids: approval.dig('attributes', 'lob-ids') || [],
              user: user_info || {},
              user_email: user_email,
              project: project_data || {}
            }
          end
    
          # Handle paging logic
          if approvals.length == page_size
            closure['current_page'] = current_page + 1
            should_poll_more = true
          else
            closure['current_page'] = 1
            should_poll_more = false
          end
    
          {
            events: events,
            next_poll: closure,
            can_poll_more: should_poll_more
          }
    
        rescue => e
          puts "Error in poll: #{e.message}"
          error("Polling failed: #{e.message}")
        end
      end,
    
      dedup: lambda do |approval|
        approval[:id]
      end,
    
      output_fields: lambda do |object_definitions|
        [
          { name: 'id', type: 'integer', label: 'Approval ID' },
          { name: 'type', type: 'string' },
          {
            name: 'status',
            type: 'string',
            control_type: 'select',
            pick_list: [
              ['Optional', 'optional'],
              ['Approved', 'approved'],
              ['Declined', 'declined'],
              ['Rescope', 'rescope']
            ]
          },
          { name: 'role', type: 'string' },
          { name: 'comment', type: 'string', optional: true },
          { name: 'reason', type: 'string' },
          { name: 'completed_at', type: 'timestamp', optional: true },
          { name: 'approver_name', type: 'string' },
          { name: 'lob_ids', type: 'array', of: 'string' },
          {
            name: 'user',
            type: 'object',
            properties: [
              { name: 'id', type: 'string' },
              { name: 'type', type: 'string' },
              {
                name: 'attributes',
                type: 'object',
                properties: [
                  { name: 'email', type: 'string' },
                  { name: 'name', type: 'string' },
                  { name: 'privileges', type: 'object' }
                ]
              }
            ]
          },
          { name: 'user_email', type: 'string', optional: true },
          {
            name: 'project',
            type: 'object',
            properties: object_definitions['project']
          }
        ]
      end
    },

    approved_projects: {
      title: "Approved Projects",
      subtitle: "Get projects that have been approved",
      description: "Get projects that have been approved since the last poll",
      help: "This trigger polls for projects that have been approved since the specified time. On first run, it will use the provided 'since' time. On subsequent runs, it will use the last successful poll time.",
      
      config_fields: [
        {
          name: "include_project_variables",
          label: "Include Individual Project Variables",
          type: "boolean",
          control_type: "checkbox",
          optional: true,
          sticky: true,
          default: true,
          hint: "When enabled, individual project variables will be available as separate data pills (e.g., project_variable_custom_code). When disabled, only the project-variables array will be available."
        }
      ],
      
      input_fields: lambda do |_object_definitions|
        [
          {
            name: "since",
            label: "When first started, this recipe should pick up events from",
            type: "timestamp",
            optional: false,
            sticky: true,
            hint: "When you start recipe for the first time, it picks up projects from this specified date and time. The API filters by day, so any projects approved on or after this date will be included. Defaults to yesterday to ensure no approvals are missed."
          }
        ]
      end,

      poll: lambda do |connection, input, closure|
        puts "=== STARTING APPROVED PROJECTS POLL ==="
        puts "Input: #{input.inspect}"
        puts "Initial closure: #{closure.inspect}"
        puts "Connection keys: #{connection.keys if connection.is_a?(Hash)}"
        
        # Get config fields
        config_fields = connection['config_fields'] || {}
        include_project_variables = config_fields['include_project_variables'] != false  # Default to true
        puts "Include project variables: #{include_project_variables}"
        
        # Initialize closure if it doesn't exist
        closure = closure || {}
        puts "Closure after initialization: #{closure.inspect}"
        
        # Get account information using the reusable method
        puts "Calling get_account_info..."
        account_info = call('get_account_info', connection)
        puts "Account info response: #{account_info.inspect}"
        account_slug = account_info[:account_slug]
        
        puts "Account slug: #{account_slug}"
        
        # Get the last poll time from closure or input
        # Convert to date format since API only supports per-day filtering
        puts "Determining last poll date..."
        puts "  closure['last_poll_date']: #{closure['last_poll_date']}"
        puts "  input['since']: #{input['since']}"
        
        last_poll_date = if closure['last_poll_date']
          puts "  Using closure last_poll_date: #{closure['last_poll_date']}"
          closure['last_poll_date']
        elsif input['since']
          formatted_date = input['since'].to_time.strftime('%Y-%m-%d')
          puts "  Using input since date, formatted: #{formatted_date}"
          formatted_date
        else
          default_date = (Time.now - 1.day).strftime('%Y-%m-%d')
          puts "  Using default date (yesterday): #{default_date}"
          default_date
        end
        
        puts "Final last_poll_date: #{last_poll_date}"
        
        begin
          puts "=== MAKING API REQUEST ==="
          puts "URL: /#{account_slug}/v1/projects"
          puts "Filter: filter[approved-at.after]=#{last_poll_date}"
          puts "Expected URL format: /#{account_slug}/v1/projects?filter[approved-at.after]=#{last_poll_date}&include=..."
          
          # Include basic related data that might be useful
          includes = ['client', 'sales-executive', 'presales-engineer', 'business-unit']
          
          # Try different parameter formats to see which one works
          # Let's try multiple filter formats to see if any work
          params = { 
            'filter[approved-at.after]' => last_poll_date,
            'include' => includes.join(',')
          }
          puts "Request params: #{params.inspect}"
          
          # Try using the same approach as the search projects action
          response = get("/#{account_slug}/v1/projects")
                        .headers('Accept': 'application/vnd.api+json')
                        .params(params)
          
          puts "=== REQUEST DEBUG INFO ==="
          puts "Base URL: https://api.scopestack.io"
          puts "Path: /#{account_slug}/v1/projects"
          puts "Filter parameter: filter[approved-at.after]=#{last_poll_date}"
          puts "Full expected URL: https://api.scopestack.io/#{account_slug}/v1/projects?filter[approved-at.after]=#{last_poll_date}&include=#{includes.join(',')}"
          
          puts "=== API RESPONSE RECEIVED ==="
          puts "Response class: #{response.class}"
          puts "Response keys: #{response.keys if response.is_a?(Hash)}"
          puts "Response meta: #{response['meta'] if response.is_a?(Hash)}"
          puts "Response links: #{response['links'] if response.is_a?(Hash)}"
          
          projects = response['data'] || []
          puts "Projects array size: #{projects.size}"
          
          if projects.size > 0
            puts "First project sample (truncated):"
            first_project = projects.first
            puts "  ID: #{first_project['id']}"
            puts "  Type: #{first_project['type']}"
            puts "  Approved at: #{first_project.dig('attributes', 'approved-at')}"
            puts "  Project name: #{first_project.dig('attributes', 'project-name')}"
            puts "  Status: #{first_project.dig('attributes', 'status')}"
            puts "  Created at: #{first_project.dig('attributes', 'created-at')}"
            puts "  Updated at: #{first_project.dig('attributes', 'updated-at')}"
            puts "  Available attributes: #{first_project['attributes'].keys.join(', ')}" if first_project['attributes']
            
            # Show a few more projects to see the date range
            puts "Sample of project dates:"
            projects.first(5).each do |project|
              puts "  Project #{project['id']}: #{project.dig('attributes', 'approved-at')} (#{project.dig('attributes', 'project-name')})"
            end
            
            # Show the date range of all projects
            if projects.size > 5
              puts "Date range of all projects:"
              dates = projects.map { |p| p.dig('attributes', 'approved-at') }.compact.sort
              puts "  Earliest: #{dates.first}"
              puts "  Latest: #{dates.last}"
              puts "  Total unique dates: #{dates.uniq.size}"
            end
          end
          
          # Since API only filters by day, we need to filter out projects that were already processed
          # by checking if we've seen them before with the same approved_at timestamp
          processed_projects = closure['processed_projects'] || {}
          puts "Processed projects count: #{processed_projects.size}"
          puts "Processed projects keys: #{processed_projects.keys.first(5)}" if processed_projects.size > 0
          
          puts "=== FILTERING PROJECTS ==="
          puts "Filtering by date: #{last_poll_date}"
          puts "Converting last_poll_date to Time object for comparison..."
          filter_date = Date.parse(last_poll_date).to_time
          puts "Filter date (Time): #{filter_date}"
          
          approved_projects = projects.select do |project|
            begin
              project_id = project['id']
              approved_at = project.dig('attributes', 'approved-at')
              status = project.dig('attributes', 'status')
              puts "  Checking project #{project_id}: approved_at=#{approved_at}, status=#{status}"
              
              # Skip projects that don't have an approved_at timestamp
              next false unless approved_at
              
              # Parse the approved_at timestamp
              project_approved_time = Time.parse(approved_at)
              puts "    Project approved time: #{project_approved_time}"
              puts "    Filter date: #{filter_date}"
              puts "    Is after filter date? #{project_approved_time > filter_date}"
              
              # Manual date filtering since API filter doesn't seem to work
              unless project_approved_time > filter_date
                puts "    -> Project approved before filter date, skipping"
                next false
              end
              
              # Check if we've already processed this project with this exact timestamp
              if processed_projects[project_id] == approved_at
                puts "    -> Already processed with same timestamp, skipping"
                next false
              end
              
              puts "    -> New or approved project, including"
              true
            rescue => e
              puts "    -> Error processing project #{project['id']}: #{e.message}"
              false
            end
          end
          
          puts "Found #{approved_projects.size} new/approved projects"
          
          # Update processed projects tracking
          puts "=== UPDATING PROCESSED PROJECTS TRACKING ==="
          approved_projects.each do |project|
            project_id = project['id']
            approved_at = project.dig('attributes', 'approved-at')
            processed_projects[project_id] = approved_at
            puts "  Marked project #{project_id} as processed with timestamp #{approved_at}"
          end
          
          # Clean up old processed projects (keep only last 1000 to prevent memory issues)
          if processed_projects.size > 1000
            puts "Cleaning up processed projects cache (was #{processed_projects.size})"
            # Keep only the most recent 500 entries
            processed_projects = processed_projects.to_a.last(500).to_h
            puts "After cleanup: #{processed_projects.size} entries"
          end
          
          # Format each project into an event
          puts "=== FORMATTING EVENTS ==="
          events = approved_projects.map do |project|
            # Extract project variables for individual field access
            project_variables = project.dig('attributes', 'project-variables') || []
            
            # Add individual project variable fields to the attributes (only if config option is enabled)
            if include_project_variables && project['attributes'] && project_variables.any?
              project_variables.each do |var|
                var_name = var['name']
                var_value = var['value']
                var_type = var['variable_type']
                select_options = var['select_options'] || []
                
                # Create field name with prefix to avoid conflicts
                field_name = "project_variable_#{var_name}"
                
                # Convert value based on variable type
                case var_type
                when 'number'
                  project['attributes'][field_name] = var_value&.to_i
                when 'date'
                  project['attributes'][field_name] = var_value
                else
                  project['attributes'][field_name] = var_value
                end
                
                # For select variables, also add the display key
                if var_type == 'text' && select_options.any? && var_value.present?
                  # Find the matching select option
                  matching_option = select_options.find { |opt| opt['value'] == var_value }
                  if matching_option
                    project['attributes']["#{field_name}_key"] = matching_option['key']
                  end
                end
              end
            end
            
            puts "  Created event for project #{project['id']} with #{project_variables.size} project variables"
            project
          end
          
          # Update closure with current date and processed projects
          current_date = Time.now.strftime('%Y-%m-%d')
          next_closure = {
            'last_poll_date': current_date,
            'processed_projects': processed_projects
          }
          
          puts "=== RETURNING RESPONSE ==="
          puts "Events count: #{events.size}"
          puts "Next closure last_poll_date: #{next_closure['last_poll_date']}"
          puts "Next closure processed_projects count: #{next_closure['processed_projects']&.size || 0}"
          puts "Updated closure: #{next_closure.inspect}"
          
          result = {
            events: events,
            next_poll: next_closure,
            can_poll_more: false
          }
          
          puts "Final result: #{result.inspect}"
          puts "=== POLL COMPLETED ==="
          
          result
        rescue => e
          puts "=== ERROR IN POLL ==="
          puts "Error class: #{e.class}"
          puts "Error message: #{e.message}"
          puts "Error backtrace:"
          puts e.backtrace.first(10).join("\n")
          error("Polling failed: #{e.message}")
        end
      end,

      dedup: lambda do |project|
        # The project parameter here is the full project object from the API
        project_id = project['id']
        approved_at = project.dig('attributes', 'approved-at')
        puts "Dedup - Project ID: #{project_id}, Approved at: #{approved_at}"
        dedup_key = "#{project_id}@#{approved_at}"
        puts "Generated dedup key for project #{project_id}: #{dedup_key}"
        dedup_key
      end,

      output_fields: lambda do |object_definitions, connection, config_fields|
        # Start with the base project fields
        base_fields = object_definitions['project']
        
        # Get config option
        include_project_variables = config_fields&.dig('include_project_variables') != false  # Default to true
        
        if include_project_variables && connection
          # Get account information
          account_info = call('get_account_info', connection)
          account_slug = account_info[:account_slug]
          
          # Fetch project variables from the API
          begin
            project_variables_response = get("/#{account_slug}/v1/project-variables")
                                         .params(filter: { 'variable-context': 'project' })
                                         .headers('Accept': 'application/vnd.api+json')
                                         .after_error_response(/.*/) do |_code, body, _header, message|
                                           puts "Failed to fetch project variables for schema: #{message}: #{body}"
                                           nil
                                         end
            
            if project_variables_response && project_variables_response['data']
              # Find the attributes field
              attributes_field = base_fields.find { |field| field[:name] == 'attributes' }
              if attributes_field && attributes_field[:properties]
                # Add individual project variable fields to the schema
                project_variables_response['data'].each do |var|
                  var_name = var['attributes']['name']
                  var_label = var['attributes']['label']
                  var_type = var['attributes']['variable-type']
                  
                  # Create field name with prefix
                  field_name = "project_variable_#{var_name}"
                  
                  # Determine field type based on variable type
                  field_type = case var_type
                              when 'number' then 'number'
                              when 'date' then 'date'
                              else 'string'
                              end
                  
                  # Add the field to the schema
                  attributes_field[:properties] << {
                    name: field_name,
                    type: field_type,
                    label: "Project Variable: #{var_label}",
                    hint: "Value of the #{var_name} project variable",
                    optional: true
                  }
                end
              end
            end
          rescue => e
            puts "Error fetching project variables for schema: #{e.message}"
          end
        end
        
        base_fields
      end
    }

  },

  methods: {
    get_account_info: lambda do |connection|
      account_slug = connection['account_slug']
      account_id = connection['account_id']
      
      # If either value is missing, try to fetch them from the API
      if !account_slug.present? || !account_id.present?
        # Make API call to get user info
        response = get("/v1/me")
                   .headers('Accept': 'application/vnd.api+json')
                   .after_error_response(/.*/) do |code, body, _header, message|
                     case code
                     when 401, 403
                       error("Authentication error - please check your credentials: #{message}")
                     else
                       error("Failed to fetch account information (#{code}): #{message}: #{body}")
                     end
                   end

        # Extract values from response
        account_slug ||= response.dig("data", "attributes", "account-slug")
        account_id ||= response.dig("data", "attributes", "account-id")
      end
      
      # Verify we have both values
      if !account_slug.present?
        error("Account slug is required for this operation. Please ensure your connection is properly configured.")
      end
      
      if !account_id.present?
        error("Account ID is required for this operation. Please ensure your connection is properly configured.")
      end
      
      {
        account_slug: account_slug,
        account_id: account_id
      }
    end,

    process_domain_field: lambda do |domain_input, is_url = false|
      return nil if domain_input.blank?
      
      # Strip leading and trailing whitespace
      domain = domain_input.strip
      
      # Convert string boolean to actual boolean
      is_url_boolean = is_url == "true" || is_url == true
      
      # If explicitly marked as URL or looks like a URL (contains http:// or https://)
      if is_url_boolean || domain.match?(/^https?:\/\//i)
        # If it's already a clean domain (no protocol), process it
        if domain.match?(/^(www\.)?[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}$/i)
          # Remove www if present and return clean domain
          return domain.gsub(/^www\./i, '')
        end
        
        # Validate full URL format
        unless domain.match?(/^https?:\/\/[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}/i)
          error("Invalid URL format. Please provide a valid URL (e.g., https://www.example.com or http://example.org) or a clean domain (e.g., example.com)")
        end
        
        # Extract domain from URL
        begin
          # Remove protocol and www if present
          domain = domain.gsub(/^https?:\/\//i, '').gsub(/^www\./i, '')
          # Remove everything after the first slash (path, query params, etc.)
          domain = domain.split('/').first
          # Remove port if present
          domain = domain.split(':').first
          
          # Final validation - ensure we have a clean domain
          unless domain.match?(/^[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}$/)
            error("Unable to extract valid domain from URL. Please check the URL format.")
          end
        rescue => e
          error("Failed to process URL '#{domain_input}': #{e.message}")
        end
      else
        # For non-URL inputs, validate no spaces and trim
        if domain.include?(' ')
          error("Domain cannot contain spaces when not marked as a URL. Please remove spaces or mark as a URL if this is a web address.")
        end
        
        # Remove any leading/trailing whitespace that might have been missed
        domain = domain.strip
      end
      
      # Return the processed domain
      domain
    end
  },

  actions: {

    get_current_user: {
      title: "Get Current User",
      subtitle: "Get information about the currently authenticated user",
      description: "Get current <span class='provider'>user</span> information in <span class='provider'>ScopeStack</span>",
      help: "Retrieves information about the currently authenticated user, including their profile details, account information, and privileges.",

      input_fields: lambda do |_object_definitions|
        []
      end,

      execute: lambda do |connection, _input|
        response = get("/v1/me")
                   .after_error_response(/.*/) do |code, body, _header, message|
                     case code
                     when 401, 403
                       error("Authentication failed or insufficient permissions. Please check your credentials: #{message}")
                     when 500..599
                       error("ScopeStack server error occurred. Please try again later: #{message}")
                     else
                       error("Failed to fetch current user information (#{code}): #{message}: #{body}")
                     end
                   end

        response
      end,

      output_fields: lambda do |_object_definitions|
        [
          {
            name: 'data',
            type: 'object',
            properties: [
              {
                name: 'id',
                type: 'string',
                label: 'User ID'
              },
              {
                name: 'type',
                type: 'string',
                label: 'Type',
                hint: 'Always "mes" for this resource type'
              },
              {
                name: 'links',
                type: 'object',
                properties: [
                  {
                    name: 'self',
                    type: 'string',
                    label: 'Self Link'
                  }
                ]
              },
              {
                name: 'attributes',
                type: 'object',
                properties: [
                  {
                    name: 'name',
                    type: 'string',
                    label: 'User Name'
                  },
                  {
                    name: 'title',
                    type: 'string',
                    label: 'Title'
                  },
                  {
                    name: 'email',
                    type: 'string',
                    label: 'Email'
                  },
                  {
                    name: 'phone',
                    type: 'string',
                    label: 'Phone'
                  },
                  {
                    name: 'account-id',
                    type: 'integer',
                    label: 'Account ID'
                  },
                  {
                    name: 'account-slug',
                    type: 'string',
                    label: 'Account Slug'
                  },
                  {
                    name: 'privileges',
                    type: 'array',
                    of: 'object',
                    label: 'Privileges',
                    properties: [
                      {
                        name: 'privilege',
                        type: 'string',
                        label: 'Privilege'
                      },
                      {
                        name: 'access-level',
                        type: 'string',
                        label: 'Access Level'
                      }
                    ]
                  },
                  {
                    name: 'uuid',
                    type: 'string',
                    label: 'UUID'
                  },
                  {
                    name: 'site-admin',
                    type: 'boolean',
                    label: 'Site Admin'
                  }
                ]
              }
            ]
          }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        {
          "data" => {
            "id" => "4029",
            "type" => "mes",
            "links" => {
              "self" => "https://api.scopestack.io/v1/mes"
            },
            "attributes" => {
              "name" => "Alex Reynolds - Site Admin",
              "title" => "",
              "email" => "alex@scopestack.io",
              "phone" => "",
              "account-id" => 864,
              "account-slug" => "computacenter",
              "privileges" => [
                {
                  "privilege" => "projects.overview",
                  "access-level" => "purge"
                },
                {
                  "privilege" => "projects.psa",
                  "access-level" => "manage"
                }
              ],
              "uuid" => "47ec0ea9-bb2b-4ab6-9d3b-8fbbbcd84824",
              "site-admin" => true
            }
          }
        }
      end
    },



    get_client: {
      title: "Get Client",
      subtitle: "Find a client in ScopeStack by ID, name, or domain",
      description: "Find <span class='provider'>client</span> in <span class='provider'>ScopeStack</span>",
      help: "Finds a client using Client ID, Name, or Domain. If Client ID is provided, it takes precedence. When searching by name or domain, it will return the first matching client.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "client_id",
            label: "Client ID",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "The unique identifier of the client. If provided, this will be used to find the client. If not provided, Client Name or Domain will be used instead.",
            sticky: true
          },
          {
            name: "client_name",
            label: "Client Name",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "The name of the client to find. If Client ID is not provided, this will be used to search for the client.",
            sticky: true
          },
          {
            name: "domain",
            label: "Domain",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "Enter a domain (e.g., google.com) or identifier (e.g., client-123). If searching for a stored domain, use the same format it was stored in.",
            sticky: true
          },
          {
            name: "domain_is_url",
            label: "Domain is a Web URL",
            type: "string",
            control_type: "select",
            optional: true,
            default: "true",
            pick_list: [
              ["Yes", "true"],
              ["No", "false"]
            ],
            hint: "Select \"Yes\" if the domain field contains a full URL (e.g., https://www.example.com). The system will extract just the domain (example.com). Select \"No\" for plain text identifiers (no spaces allowed).",
            sticky: true
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Determine which parameter to use based on what's provided
        if input['client_id'].present?
          # If ID is provided, use it
          response = get("/#{account_slug}/v1/clients/#{input['client_id']}")
            .headers('Accept': 'application/vnd.api+json')
            .after_error_response(/.*/) do |code, body, _header, message|
              case code
              when 404
                error("Client with ID '#{input['client_id']}' not found")
              when 401, 403
                error("Authentication error - please check your credentials: #{message}")
              else
                error("Failed to fetch client (#{code}): #{message}: #{body}")
              end
            end

          # Debug response
          puts "API Response type: #{response.class}"
          puts "API Response content: #{response.inspect}"

          # Convert response to hash if it's not already
          response = response.to_hash if response.respond_to?(:to_hash)

          # Validate response structure
          unless response.is_a?(Hash)
            error("Invalid response format from API. Expected Hash, got: #{response.class}. Response: #{response.inspect}")
          end

          unless response.key?('data')
            error("Invalid response format from API. Missing 'data' key. Response: #{response.inspect}")
          end

          response['data']
        elsif input['client_name'].present? || input['domain'].present?
          # If name or domain is provided, search by those parameters
          filter_params = {}
          filter_params[:name] = input['client_name'] if input['client_name'].present?
          filter_params[:domain] = call('process_domain_field', input['domain'], input['domain_is_url']) if input['domain'].present?

          # Log search parameters for troubleshooting
          puts "Searching for client with parameters: #{filter_params.inspect}"

          begin
          response = get("/#{account_slug}/v1/clients")
            .headers('Accept': 'application/vnd.api+json')
              .params(filter: filter_params)
              .after_error_response(/.*/) do |code, body, _header, message|
                case code
                when 400
                  error("Invalid search parameters: #{message}: #{body}")
                when 401, 403
                  error("Authentication error - please check your credentials: #{message}")
                when 404
                  error("Resource not found - please check your account slug: #{message}")
                when 429
                  error("Rate limit exceeded - please try again later: #{message}")
                else
                  error("Failed to search for client (#{code}): #{message}: #{body}")
                end
              end

            # Debug response
            puts "API Response type: #{response.class}"
            puts "API Response content: #{response.inspect}"

            # Convert response to hash if it's not already
            response = response.to_hash if response.respond_to?(:to_hash)

            # Validate response structure
            unless response.is_a?(Hash)
              error("Invalid response format from API. Expected Hash, got: #{response.class}. Response: #{response.inspect}")
            end

            unless response.key?('data')
              error("Invalid response format from API. Missing 'data' key. Response: #{response.inspect}")
            end

            # Check if we found any results
            if response['data'].nil? || response['data'].empty?
            search_criteria = []
              search_criteria << "name: '#{input['client_name']}'" if input['client_name'].present?
              search_criteria << "domain: '#{filter_params[:domain]}'" if input['domain'].present?
              error("No client found matching #{search_criteria.join(' and ')}. Please verify the search criteria.")
            end

            # If searching by domain and multiple results found, error
            if input['domain'].present? && response['data'].length > 1
              matching_clients = response['data'].map { |c| "#{c.dig('attributes', 'name')} (ID: #{c['id']})" }
              error("Multiple clients found with domain '#{filter_params[:domain]}':\n#{matching_clients.join("\n")}\nPlease use Client ID for exact match.")
            end

            # If searching by name, handle exact matches
            if input['client_name'].present?
              # Find exact name matches
              exact_matches = response['data'].select { |client| client.dig('attributes', 'name') == input['client_name'] }
              
              # Error if multiple exact matches
              if exact_matches.length > 1
                matching_clients = exact_matches.map { |c| "#{c.dig('attributes', 'name')} (ID: #{c['id']}, Domain: #{c.dig('attributes', 'domain')})" }
                error("Multiple clients found with exact name '#{input['client_name']}':\n#{matching_clients.join("\n")}\nPlease use Client ID for exact match.")
              end
              
              # If we have one exact match, return it
              if exact_matches.length == 1
                puts "Found exact name match: #{exact_matches.first['id']}"
                return exact_matches.first
              end
              
              # If we have partial matches but no exact match
              puts "No exact name match found. Using first partial match: #{response['data'].first['id']}"
              return response['data'].first
            end

            # Return the first/only match for other cases
            puts "Returning match: #{response['data'].first['id']}"
            response['data'].first
          end
        else
          error("At least one of Client ID, Name, or Domain must be provided to find the client. Received: #{input.reject { |_, v| v.blank? }.keys.join(', ')}")
        end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['client']
      end,

      sample_output: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Get a sample client
        response = get("/#{account_slug}/v1/clients")
                    .params(limit: 1)
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |_code, body, _header, message|
                      error("Failed to fetch sample client: #{message}: #{body}")
                    end

        response['data'].first || {}
      end
    },

    create_or_update_client: {
      title: "Create or Update Client",
      subtitle: "Create a new client or update an existing one in ScopeStack",
      description: "Create or update <span class='provider'>client</span> in <span class='provider'>ScopeStack</span>",
      help: "This action creates a new client or updates an existing one. If a client ID is provided, it will attempt to update that specific client. If no client ID is provided, it will search for existing clients by domain first (if provided), then by name if no domain match is found. When a single client is found by domain, that client will be updated. The name may be changed even if it differs. If 'Error on Domain Mismatch' is 'Yes', changing, adding, or clearing the client's domain is blocked unless you use Client ID. If no match is found, it will create a new client.",

      input_fields: lambda do |_object_definitions, connection|
        # Static fields
        fields = [
          {
            name: "client_id",
            label: "Client ID",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "If provided, updates the existing client. If the client is not found, the action will fail. If not provided, creates a new client."
          },
          {
            name: "name",
            label: "Name",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "Name of the client. When no Client ID or domain is provided, the action will search for existing clients by this name."
          },
          {
            name: "domain",
            label: "Domain",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "Enter a domain (e.g., google.com) or identifier (e.g., client-123). If entering a URL, select 'Yes' for 'Domain is a Web URL' below. When no Client ID is provided, the action will search for existing clients by this domain first."
          },
          {
            name: "domain_is_url",
            label: "Domain is a Web URL",
            type: "string",
            control_type: "select",
            optional: true,
            default: "true",
            pick_list: [
              ["Yes", "true"],
              ["No", "false"]
            ],
            hint: "Select \"Yes\" if the domain field contains a full URL (e.g., https://www.example.com). The system will extract and store just the domain (example.com). Select \"No\" for plain text identifiers (no spaces allowed)."
          },
          {
            name: "msa_date",
            label: "MSA Date",
            type: "string",
            control_type: "date",
            optional: true,
            hint: "Master Service Agreement date"
          },
          {
            name: "error_on_domain_mismatch",
            label: "Error on Domain Mismatch",
            type: "string",
            control_type: "select",
            optional: true,
            default: "false",
            pick_list: [
              ["No", "false"],
              ["Yes", "true"]
            ],
            hint: "When set to 'Yes', the action will error if it finds a client with matching name but different domain, if the existing client has no domain but you're providing one, or if the existing client has a domain but you're not providing one (to prevent clearing domains). When 'No', it will proceed with updating the existing client."
          }
        ]

        # Add dynamic user-defined fields for client context
        begin
          account_info = call('get_account_info', connection)
          account_slug = account_info[:account_slug]
          
          variables_response = get("/#{account_slug}/v1/project-variables")
                               .params(filter: { 'variable-context': 'client' })
                               .headers('Accept': 'application/vnd.api+json')
                               .after_error_response(/.*/) do |code, body, _header, message|
                                 case code
                                 when 401, 403
                                   error("Authentication failed or insufficient permissions to access client variables. Please check your credentials.")
                                 when 500..599
                                   error("ScopeStack server error occurred while fetching client variables. Please try again later.")
                                 else
                                   error("Failed to fetch client variables: #{message}. Response: #{body}")
                                 end
                               end

          if variables_response['data']&.any?
            variables_response['data'].each do |var|
              attrs = var['attributes']
              var_name = attrs['name']
              var_label = attrs['label']
              var_hint = "User defined field: #{var_label}"
              
              # Skip if this is a select field with no options, or if required but with empty select options
              skip_field = false
              if attrs['variable-type'] == 'select'
                if attrs['select-options'].nil? || attrs['select-options'].empty?
                  skip_field = true
                end
              end

              next if skip_field
              
              dynamic_field = {
                name: "var_#{var_name}",
                label: var_label,
                hint: var_hint,
                optional: !attrs['required']
              }
              
              case attrs['variable-type']
              when 'number'
                dynamic_field[:type] = 'number'
                dynamic_field[:control_type] = 'number'
              when 'date'
                dynamic_field[:type] = 'date'
                dynamic_field[:control_type] = 'date'
              when 'select'
                dynamic_field[:type] = 'string'
                dynamic_field[:control_type] = 'select'
                dynamic_field[:pick_list] = attrs['select-options']&.map { |opt| [opt['label'], opt['value']] } || []
              else
                dynamic_field[:type] = 'string'
                dynamic_field[:control_type] = 'text'
              end
              
              fields << dynamic_field
            end
          end
        rescue StandardError => e
          puts "Error fetching client variables: #{e.message}"
        end

        fields
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Fetch client variables to get their types and process user-defined fields
        user_defined_fields = []
        begin
          variables_response = get("/#{account_slug}/v1/project-variables")
                               .params(filter: { 'variable-context': 'client' })
                               .headers('Accept': 'application/vnd.api+json')
                               .after_error_response(/.*/) do |code, body, _header, message|
                                 case code
                                 when 401, 403
                                   error("Authentication failed or insufficient permissions to access client variables. Please check your credentials.")
                                 when 500..599
                                   error("ScopeStack server error occurred while fetching client variables. Please try again later.")
                                 else
                                   error("Failed to fetch client variables: #{message}. Response: #{body}")
                                 end
                               end

          # Create lookup for variable types
          variable_types = variables_response['data']&.each_with_object({}) do |var, hash|
            hash[var['attributes']['name']] = var['attributes']
          end || {}

          # Helper function to process variable value based on its type
          process_variable_value = lambda do |name, value|
            return nil if value.nil? || value == ""
            var_attrs = variable_types[name]
            return value unless var_attrs  # Return as is if we don't have type info
            
            case var_attrs['variable-type']
            when 'number'
              if var_attrs['select-options'].present?
                # For number select fields, find the matching option value
                option = var_attrs['select-options'].find { |opt| opt['key'].to_s == value.to_s }
                option ? option['value'].to_i : value.to_i
              else
                value.to_i
              end
            when 'date'
              value.to_s  # Ensure date is sent as string
            when 'select', 'text'
              if var_attrs['select-options'].present?
                # For text/select fields, find the matching option value
                option = var_attrs['select-options'].find { |opt| opt['key'].to_s == value.to_s }
                option ? option['value'].to_s : value.to_s
              else
                value.to_s
              end
            else
              value.to_s
            end
          end

          # Extract and process user-defined fields from input
          user_defined_fields = input.keys
                                     .select { |k| k.start_with?('var_') }
                                     .map do |k|
                                       var_name = k.sub('var_', '')
                                       var_value = process_variable_value.call(var_name, input[k])
                                       { name: var_name, value: var_value }
                                     end.reject { |v| v[:value].nil? }
        rescue StandardError => e
          puts "Error processing client variables: #{e.message}"
        end

        # If we have a client ID, update the existing client
        if input['client_id'].present?
          # Check if client exists
          response = get("/#{account_slug}/v1/clients/#{input['client_id']}")
                     .headers('Accept': 'application/vnd.api+json')
                     .after_error_response(/.*/) do |_code, body, _header, message|
                       error("Failed to find client: #{message}: #{body}")
                     end

          # Prepare the update payload
          payload_attributes = {
            name: input['name'],
            domain: call('process_domain_field', input['domain'], input['domain_is_url']),
            "msa-date": input['msa_date']
          }
          
          # Add user-defined fields if any
          if user_defined_fields.any?
            payload_attributes['user-defined-fields'] = user_defined_fields
          end
          
          payload = {
            data: {
              type: "clients",
              id: input['client_id'],
              attributes: payload_attributes
            }
          }

          # Update the existing client
          response = patch("/#{account_slug}/v1/clients/#{input['client_id']}")
                     .payload(payload)
                     .headers('Accept': 'application/vnd.api+json',
                             'Content-Type': 'application/vnd.api+json')
                     .after_error_response(/.*/) do |_code, body, _header, message|
                       error("Failed to update client: #{message}: #{body}")
                     end
        else
          # Search for existing client - try domain first, then name
          filter_params = {}
          search_type = nil
          existing_client = nil
          
          # First, try to search by domain if provided
          if input['domain'].present?
            filter_params[:domain] = call('process_domain_field', input['domain'], input['domain_is_url'])
            search_type = "domain"
            
            encoded_domain = URI.encode_www_form_component(filter_params[:domain].to_s).gsub('+', '%20')
            search_response = get("/#{account_slug}/v1/clients?filter%5Bdomain%5D=#{encoded_domain}&filter%5Bactive%5D=true,false")
                             .headers('Accept': 'application/vnd.api+json')
                             .after_error_response(/.*/) do |_code, body, _header, message|
                               error("Failed to search for client by domain: #{message}: #{body}")
                             end

            # If we found clients by domain, enforce selection rules
            if search_response['data']&.any?
              candidates = search_response['data']
              active_candidates = candidates.select { |c| c.dig('attributes', 'active') == true }
              inactive_candidates = candidates.select { |c| c.dig('attributes', 'active') == false }

              # If multiple active clients, error (ambiguous)
              if active_candidates.length > 1
                matching_clients = active_candidates.map { |c| "#{c.dig('attributes', 'name')} (ID: #{c['id']})" }
                error("Multiple ACTIVE clients found with domain '#{filter_params[:domain]}':\n#{matching_clients.join("\n")}\nPlease use Client ID for exact match.")
              elsif active_candidates.length == 1
                # Exactly one active client - ignore inactive ones and use the active one
                existing_client = active_candidates.first
              else
                # No active candidates, only inactive
                if inactive_candidates.length > 1
                  # Multiple inactive matches -> require explicit Client ID
                  matching_clients = inactive_candidates.map { |c| "#{c.dig('attributes', 'name')} (ID: #{c['id']})" }
                  error("Multiple INACTIVE clients found with domain '#{filter_params[:domain]}':\n#{matching_clients.join("\n")}\nPlease use Client ID for exact match.")
                elsif inactive_candidates.length == 1
                  # Exactly one inactive -> proceed and reactivate later
                  existing_client = inactive_candidates.first
                end
              end
              
              # Add domain protection checks when error_on_domain_mismatch is enabled
              if existing_client && input['error_on_domain_mismatch'] == "true"
                existing_domain = existing_client.dig('attributes', 'domain')
                provided_domain = call('process_domain_field', input['domain'], input['domain_is_url'])
                
                # Block changing an existing non-blank domain to a different value
                if existing_domain.present? && provided_domain.present? && existing_domain != provided_domain
                  error("Refusing to change domain from '#{existing_domain}' to '#{provided_domain}'. Use Client ID or set 'Error on Domain Mismatch' to 'No'.")
                end
                
                # Block adding a domain when the existing client has none (prevents silent assignment)
                if existing_domain.blank? && provided_domain.present?
                  error("Refusing to add domain '#{provided_domain}' to existing client. Use Client ID or set 'Error on Domain Mismatch' to 'No'.")
                end
                
                # Block clearing domain if existing has one but input is blank
                if existing_domain.present? && provided_domain.blank?
                  error("Refusing to clear existing domain '#{existing_domain}'. Use Client ID or set 'Error on Domain Mismatch' to 'No'.")
                end
              end
            end
          end
          
          # If no client found by domain, try searching by name
          if existing_client.nil? && input['name'].present?
            filter_params = { name: input['name'] }
            search_type = "name"
            
            encoded_name = URI.encode_www_form_component(input['name'].to_s.strip).gsub('+', '%20')
            search_response = get("/#{account_slug}/v1/clients?filter%5Bname%5D=#{encoded_name}&filter%5Bactive%5D=true,false")
                             .headers('Accept': 'application/vnd.api+json')
                             .after_error_response(/.*/) do |_code, body, _header, message|
                               error("Failed to search for client by name: #{message}: #{body}")
                             end

            # If we found a client by name, check for domain mismatch
            if search_response['data']&.any?
              # Check for EXACT name matches only (same logic as Find Client action)
              exact_matches = search_response['data'].select { |client| client.dig('attributes', 'name') == input['name'] }
              
              # Only proceed if we have an exact match
              if exact_matches.any?
                name_match_client = exact_matches.find { |c| c.dig('attributes', 'active') == true } || exact_matches.first
              else
                # No exact match found, will create new client
                name_match_client = nil
              end
              
              # Only proceed with domain mismatch checking if we found an exact match
              if name_match_client.present?
                existing_domain = name_match_client.dig('attributes', 'domain')
                
                # Convert string boolean to actual boolean
                error_on_mismatch = input['error_on_domain_mismatch'] == "true"
                
                if error_on_mismatch
                # Check for domain conflicts when error checking is enabled
                if input['domain'].present?
                  provided_domain = call('process_domain_field', input['domain'], input['domain_is_url'])
                  
                  if existing_domain.present? && provided_domain != existing_domain
                    # Existing client has different domain
                    error("Domain mismatch detected. Found existing client with name '#{input['name']}' but different domain.\n" +
                          "Existing client details:\n" +
                          "  - Client ID: #{name_match_client['id']}\n" +
                          "  - Name: #{name_match_client.dig('attributes', 'name')}\n" +
                          "  - Existing Domain: #{existing_domain}\n" +
                          "  - Provided Domain: #{provided_domain}\n\n" +
                          "To proceed, either:\n" +
                          "1. Use the Client ID (#{name_match_client['id']}) to update the specific client, or\n" +
                          "2. Set 'Error on Domain Mismatch' to 'No' to allow domain updates, or\n" +
                          "3. Use a different name or domain to create a new client.")
                  elsif existing_domain.blank? && provided_domain.present?
                    # Existing client has no domain, but we're trying to set one
                    error("Domain mismatch detected. Found existing client with name '#{input['name']}' but no existing domain.\n" +
                          "Existing client details:\n" +
                          "  - Client ID: #{name_match_client['id']}\n" +
                          "  - Name: #{name_match_client.dig('attributes', 'name')}\n" +
                          "  - Existing Domain: (none)\n" +
                          "  - Provided Domain: #{provided_domain}\n\n" +
                          "To proceed, either:\n" +
                          "1. Use the Client ID (#{name_match_client['id']}) to update the specific client, or\n" +
                          "2. Set 'Error on Domain Mismatch' to 'No' to allow adding domain to existing client, or\n" +
                          "3. Use a different name or domain to create a new client.")
                  else
                    # No domain conflict, proceed
                    existing_client = name_match_client
                  end
                elsif existing_domain.present?
                  # No domain provided in input, but existing client has a domain
                  error("Domain mismatch detected. Found existing client with name '#{input['name']}' that has an existing domain.\n" +
                        "Existing client details:\n" +
                        "  - Client ID: #{name_match_client['id']}\n" +
                        "  - Name: #{name_match_client.dig('attributes', 'name')}\n" +
                        "  - Existing Domain: #{existing_domain}\n" +
                        "  - Provided Domain: (none)\n\n" +
                        "To proceed, either:\n" +
                        "1. Use the Client ID (#{name_match_client['id']}) to update the specific client, or\n" +
                        "2. Set 'Error on Domain Mismatch' to 'No' to allow domain clearing, or\n" +
                        "3. Provide the existing domain value to maintain it.")
                else
                  # No domain provided and existing client has no domain
                  existing_client = name_match_client
                end
                else
                  # No error checking enabled, proceed with update (existing behavior)
                  existing_client = name_match_client
                end
              end
            end
          end
          
          # If we found an existing client, check for name conflicts before updating
          if existing_client.present?
            client_id = existing_client['id']
            reactivate_client = existing_client.dig('attributes', 'active') == false
            
            # Check if the name is already taken by a different client
            if input['name'].present?
              encoded_name = URI.encode_www_form_component(input['name'].to_s.strip).gsub('+', '%20')
              name_check_response = get("/#{account_slug}/v1/clients?filter%5Bname%5D=#{encoded_name}&filter%5Bactive%5D=true,false")
                                   .headers('Accept': 'application/vnd.api+json')
                                   .after_error_response(/.*/) do |_code, body, _header, message|
                                     puts "Failed to check for name conflicts: #{message}: #{body}"
                                     nil
                                   end
              
              if name_check_response && name_check_response['data']&.any?
                # Check for EXACT name matches only (same logic as Find Client action)
                exact_matches = name_check_response['data'].select { |client| client.dig('attributes', 'name') == input['name'] }

                # Check if any exact matches are different clients
                conflicting_clients = exact_matches.select { |c| c['id'] != client_id }

                if conflicting_clients.any?
                  # Filter conflicts: only error on active conflicts, or inactive if strict checking enabled
                  if input['error_on_domain_mismatch'] == "true"
                    # Strict mode: check all conflicts (active and inactive)
                    active_conflicts = conflicting_clients.select { |c| c.dig('attributes', 'active') == true }
                    inactive_conflicts = conflicting_clients.select { |c| c.dig('attributes', 'active') == false }
                    
                    conflicts_to_report = active_conflicts + inactive_conflicts
                  else
                    # Normal mode: only check active conflicts
                    conflicts_to_report = conflicting_clients.select { |c| c.dig('attributes', 'active') == true }
                  end

                  if conflicts_to_report.any?
                    conflicting_details = conflicts_to_report.map do |c|
                      active_status = c.dig('attributes', 'active') == true ? 'active' : 'inactive'
                      [
                        "- Client:",
                        "  - ID: #{c['id']}",
                        "  - Status: #{active_status}",
                        "  - Name: #{c.dig('attributes', 'name')}",
                        "  - Domain: #{c.dig('attributes', 'domain')}"
                      ].join("\n")
                    end.join("\n")

                    current_active_status = existing_client.dig('attributes', 'active') == true ? 'active' : 'inactive'
                    conflict_type = input['error_on_domain_mismatch'] == "true" ? "(includes inactive)" : "(active only)"

                    error(
                      [
                        "Name conflict detected. The name '#{input['name']}' is already used by another client.",
                        "Conflicting clients #{conflict_type}:",
                        conflicting_details,
                        "",
                        "Current client being updated:",
                        "- Client:",
                        "  - ID: #{client_id}",
                        "  - Status: #{current_active_status}",
                        "  - Name: #{existing_client.dig('attributes', 'name')}",
                        "  - Domain: #{existing_client.dig('attributes', 'domain')}",
                        "",
                        "This update is blocked to avoid duplicate names. To proceed, either:",
                        "1. Use a different name for this client, or",
                        "2. Reactivate and use the conflicting client instead, or",
                        "3. Purge/merge the conflicting client before retrying."
                      ].join("\n")
                    )
                  end
                end
              end
            end

            # Prepare the update payload
            payload_attributes = {
              name: input['name'],
              domain: call('process_domain_field', input['domain'], input['domain_is_url']),
              "msa-date": input['msa_date']
            }
            payload_attributes[:active] = true if reactivate_client
            
            # Add user-defined fields if any
            if user_defined_fields.any?
              payload_attributes['user-defined-fields'] = user_defined_fields
            end
            
            payload = {
              data: {
                type: "clients",
                id: client_id,
                attributes: payload_attributes
              }
            }

            # Update the existing client
            response = patch("/#{account_slug}/v1/clients/#{client_id}")
                       .payload(payload)
                       .headers('Accept': 'application/vnd.api+json',
                               'Content-Type': 'application/vnd.api+json')
                       .after_error_response(/.*/) do |_code, body, _header, message|
                         error("Failed to update existing client: #{message}: #{body}")
                       end
          else
            # No existing client found, create a new one
            payload_attributes = {
              "name" => input['name'],
              "domain" => call('process_domain_field', input['domain'], input['domain_is_url']),
              "msa-date" => input['msa_date']
            }
            
            # Add user-defined fields if any
            if user_defined_fields.any?
              payload_attributes['user-defined-fields'] = user_defined_fields
            end
            
            payload = {
              data: {
                type: "clients",
                attributes: payload_attributes
              }
            }
            
            response = post("/#{account_slug}/v1/clients")
                       .payload(payload)
                       .headers('Accept': 'application/vnd.api+json',
                               'Content-Type': 'application/vnd.api+json')
                       .after_error_response(/.*/) do |_code, body, _header, message|
                         error("Failed to create client: #{message}: #{body}")
                       end
          end
        end

        response
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['client']
      end,

      sample_output: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Get a sample client
        response = get("/#{account_slug}/v1/clients")
                    .params(limit: 1)
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |_code, body, _header, message|
                      error("Failed to fetch sample client: #{message}: #{body}")
                    end

        response['data'].first || {}
      end
    },

    update_client_active_status: {
      title: "Update Client Active Status",
      subtitle: "Activate or deactivate a client by ID",
      description: "Update the <span class='provider'>client</span> active status in <span class='provider'>ScopeStack</span> by Client ID",
      help: "Provide the ScopeStack Client ID and choose the desired active status. This action performs a targeted PATCH that only updates the client's active attribute.",

      input_fields: lambda do |_object_definitions, _connection|
        [
          { name: "client_id", label: "Client ID", type: "integer", optional: false },
          {
            name: "active",
            label: "Active",
            type: "string",
            control_type: "select",
            optional: false,
            pick_list: [["True", "true"], ["False", "false"]],
            hint: "Select True to activate the client or False to deactivate"
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        client_id = input['client_id'].to_s.strip
        error("Client ID is required") if client_id.empty?

        # Verify the client exists
        get_response = get("/#{account_slug}/v1/clients/#{client_id}")
                        .headers('Accept': 'application/vnd.api+json')
                        .after_error_response(/.*/) do |_code, body, _header, message|
                          error("Failed to fetch client #{client_id}: #{message}: #{body}")
                        end

        if get_response['data'].nil?
          error("Client with ID #{client_id} not found")
        end

        desired_active = input['active'] == 'true'

        payload = {
          data: {
            type: "clients",
            id: client_id,
            attributes: { active: desired_active }
          }
        }

        response = patch("/#{account_slug}/v1/clients/#{client_id}")
                   .headers('Accept': 'application/vnd.api+json',
                            'Content-Type': 'application/vnd.api+json')
                   .payload(payload)
                   .after_error_response(/.*/) do |_code, body, _header, message|
                     error("Failed to update client active status: #{message}: #{body}")
                   end

        response['data']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['client']
      end,

      sample_output: lambda do |connection, _input|
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        response = get("/#{account_slug}/v1/clients")
                    .params(limit: 1)
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |_code, body, _header, message|
                      error("Failed to fetch sample client: #{message}: #{body}")
                    end

        response['data'].first || {}
      end
    },

    create_or_update_sales_executive: {
      title: "Create or Update Sales Executive",
      subtitle: "Create a new sales executive or update an existing one in ScopeStack",
      description: "Create or update <span class='provider'>sales executive</span> in <span class='provider'>ScopeStack</span>",
      help: "This action creates a new sales executive or updates an existing one. If a sales executive ID is provided, it will update that sales executive. If the sales executive is not found, it will error out. If no sales executive ID is provided, it will create a new one. At least one of email or name must be provided for creation.",

      input_fields: lambda do |object_definitions|
        object_definitions['sales_executive']
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        account_id = account_info[:account_id]

        # Validate that at least one of email or name is provided for creation
        if !input['id'].present? && !input['email'].present? && !input['name'].present?
          error("At least one of email or name must be provided for creation.")
        end

        # If ID is provided, update the existing sales executive
        if input['id'].present?
          # First verify the sales executive exists
          get_response = get("/#{account_slug}/v1/sales-executives/#{input['id']}")
                        .headers('Accept': 'application/vnd.api+json')
                        .after_error_response(/.*/) do |_code, body, _header, message|
                          error("Failed to fetch sales executive: #{message}: #{body}")
                        end

          if get_response['data'].nil?
            error("Sales Executive with ID #{input['id']} not found")
          end

          # Get the existing account relationship
          existing_account = get_response['data']['relationships']['account']
          if existing_account.nil?
            error("Sales Executive #{input['id']} has no associated account")
          end

          # Prepare update payload
          payload = {
            data: {
              type: "sales-executives",
              id: input['id'].to_s,
              attributes: {}
            }
          }

          # Add fields if provided
          payload[:data][:attributes]["email"] = input['email'] if input['email'].present?
          payload[:data][:attributes]["name"] = input['name'] if input['name'].present?
          payload[:data][:attributes]["title"] = input['title'] if input['title'].present?
          payload[:data][:attributes]["phone"] = input['phone'] if input['phone'].present?
          
          response = patch("/#{account_slug}/v1/sales-executives/#{input['id']}")
                      .headers('Content-Type': 'application/vnd.api+json',
                              'Accept': 'application/vnd.api+json')
                      .payload(payload)
                      .after_error_response(/.*/) do |_code, body, _header, message|
                        error("Failed to update sales executive: #{message}: #{body}")
                      end
        else
          # No ID provided, check email first if provided
          if input['email'].present?
            email = input['email'].strip
            unless email =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
              error("Invalid email format: #{email}")
            end

            # Check if sales executive exists with this email
            se_response = get("/#{account_slug}/v1/sales-executives")
                        .headers('Accept': 'application/vnd.api+json')
                        .params(filter: { email: email })
                        .after_error_response(/.*/) do |_code, body, _header, message|
                          error("Failed to search for sales executive: #{message}: #{body}")
                        end

                        if se_response['data'].present? && se_response['data'].any?
                          if se_response['data'].size > 1
                            error("Multiple sales executives found with email #{email}. Please use the sales executive ID to update a specific one.")
                          end
                          
                          # Found single existing sales executive, update it
                          existing_se = se_response['data'].first
                          payload = {
                            data: {
                              type: "sales-executives",
                              id: existing_se['id'].to_s,
                              attributes: {}
                            }
                          }

              # Add fields if provided
              payload[:data][:attributes]["email"] = input['email'] if input['email'].present?
              payload[:data][:attributes]["name"] = input['name'] if input['name'].present?
              payload[:data][:attributes]["title"] = input['title'] if input['title'].present?
              payload[:data][:attributes]["phone"] = input['phone'] if input['phone'].present?
              
              response = patch("/#{account_slug}/v1/sales-executives/#{existing_se['id']}")
                      .headers('Content-Type': 'application/vnd.api+json',
                              'Accept': 'application/vnd.api+json')
                      .payload(payload)
                      .after_error_response(/.*/) do |_code, body, _header, message|
                        error("Failed to update sales executive: #{message}: #{body}")
                      end
              return response['data']
            else
              # Check if user exists with this email
              user_response = get("/#{account_slug}/v1/users")
                            .headers('Accept': 'application/vnd.api+json')
                            .params(filter: { email: email })
                            .after_error_response(/.*/) do |_code, body, _header, message|
                              error("Failed to check for existing user: #{message}: #{body}")
                            end

              if user_response['data'].present? && user_response['data'].any?
                existing_user = user_response['data'].first
                error("A user with email #{email} (ID: #{existing_user['id']}) already exists. Please contact your system administrator to add this user as a sales executive.")
              end
            end
          end

          # If we get here, either no email was provided or no existing sales executive/user was found with that email
          # Now check by name if provided
          if input['name'].present?
            search_response = get("/#{account_slug}/v1/sales-executives")
                            .headers('Accept': 'application/vnd.api+json')
                            .params(filter: { name: input['name'] })
                            .after_error_response(/.*/) do |_code, body, _header, message|
                              error("Failed to search for sales executive: #{message}: #{body}")
                            end

            if search_response['data'].present? && search_response['data'].any?
              # Found existing sales executive, update it
              existing_se = search_response['data'].first
              payload = {
                data: {
                  type: "sales-executives",
                  id: existing_se['id'].to_s,
                  attributes: {}
                }
              }

              # Add fields if provided
              payload[:data][:attributes]["name"] = input['name'] if input['name'].present?
              payload[:data][:attributes]["title"] = input['title'] if input['title'].present?
              payload[:data][:attributes]["phone"] = input['phone'] if input['phone'].present?
              
              response = patch("/#{account_slug}/v1/sales-executives/#{existing_se['id']}")
                      .headers('Content-Type': 'application/vnd.api+json',
                              'Accept': 'application/vnd.api+json')
                      .payload(payload)
                      .after_error_response(/.*/) do |_code, body, _header, message|
                        error("Failed to update sales executive: #{message}: #{body}")
                      end
              return response['data']
            end
          end

          # If we get here, no existing sales executive was found by email or name
          # Create a new sales executive
          payload = {
            data: {
              type: "sales-executives",
              attributes: {},
              relationships: {
                account: {
                  data: {
                    type: "accounts",
                    id: account_id.to_s
                  }
                }
              }
            }
          }

          # Add fields if provided
          payload[:data][:attributes]["email"] = input['email'] if input['email'].present?
          payload[:data][:attributes]["name"] = input['name'] if input['name'].present?
          payload[:data][:attributes]["title"] = input['title'] if input['title'].present?
          payload[:data][:attributes]["phone"] = input['phone'] if input['phone'].present?

          response = post("/#{account_slug}/v1/sales-executives")
                      .headers('Content-Type': 'application/vnd.api+json',
                              'Accept': 'application/vnd.api+json')
                      .payload(payload)
                      .after_error_response(/.*/) do |_code, body, _header, message|
                        error("Failed to create sales executive: #{message}: #{body}")
                      end
        end

        response['data']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['sales_executive']
      end,

      sample_output: lambda do |connection, input|
        {
          "id" => "123",
          "type" => "sales-executives",
          "attributes" => {
            "name" => "John Doe",
            "email" => "john.doe@example.com",
            "title" => "Sales Executive",
            "phone" => "+1 (555) 123-4567",
            "active" => true
          }
        }
      end
    },

    get_vendor: {
      title: "Get Vendor",
      subtitle: "Find a vendor in ScopeStack by ID or name",
      description: "Find <span class='provider'>vendor</span> in <span class='provider'>ScopeStack</span>",
      help: "Finds a vendor using Vendor ID or Name. If Vendor ID is provided, it takes precedence. When searching by name, it will return the first matching vendor or error if multiple exact matches are found.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "vendor_id",
            label: "Vendor ID",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "The unique identifier of the vendor. If provided, this will be used to find the vendor. If not provided, Vendor Name will be used instead.",
            sticky: true
          },
          {
            name: "vendor_name",
            label: "Vendor Name",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "The name of the vendor to find. If Vendor ID is not provided, this will be used to search for the vendor.",
            sticky: true
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Validate that at least one identifier is provided
        if input['vendor_id'].blank? && input['vendor_name'].blank?
          error("Either Vendor ID or Name must be provided to find the vendor.")
        end

        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Determine which parameter to use based on what's provided
        if input['vendor_id'].present?
          # If ID is provided, use it
          response = get("/#{account_slug}/v1/vendors/#{input['vendor_id']}")
            .headers('Accept': 'application/vnd.api+json')
            .after_error_response(/.*/) do |code, body, _header, message|
              case code
              when 404
                error("Vendor with ID '#{input['vendor_id']}' not found. Please verify the vendor ID.")
              when 401, 403
                error("Authentication failed or insufficient permissions. Please check your credentials: #{message}")
              when 500..599
                error("ScopeStack server error occurred. Please try again later: #{message}")
              else
                error("Failed to fetch vendor (#{code}): #{message}: #{body}")
              end
            end

          # Debug response
          puts "API Response type: #{response.class}"
          puts "API Response content: #{response.inspect}"

          # Convert response to hash if it's not already
          response = response.to_hash if response.respond_to?(:to_hash)

          # Validate response structure
          unless response.is_a?(Hash)
            error("Invalid response format from API. Expected Hash, got: #{response.class}. Response: #{response.inspect}")
          end

          unless response.key?('data')
            error("Invalid response format from API. Missing 'data' key. Response: #{response.inspect}")
          end

          response['data']
        elsif input['vendor_name'].present?
          # Validate vendor name is not empty
          vendor_name = input['vendor_name'].strip
          if vendor_name.blank?
            error("Vendor name cannot be empty. Please provide a valid vendor name.")
          end

          # If name is provided, search by name
          filter_params = { name: vendor_name }

          # Log search parameters for troubleshooting
          puts "Searching for vendor with parameters: #{filter_params.inspect}"

          begin
            response = get("/#{account_slug}/v1/vendors")
              .headers('Accept': 'application/vnd.api+json')
              .params(filter: filter_params)
              .after_error_response(/.*/) do |code, body, _header, message|
                case code
                when 400
                  error("Invalid search parameters. Please check the vendor name format: #{message}: #{body}")
                when 401, 403
                  error("Authentication failed or insufficient permissions. Please check your credentials: #{message}")
                when 404
                  error("Resource not found. Please check your account slug: #{message}")
                when 429
                  error("Rate limit exceeded. Please try again later: #{message}")
                when 500..599
                  error("ScopeStack server error occurred. Please try again later: #{message}")
                else
                  error("Failed to search for vendor (#{code}): #{message}: #{body}")
                end
              end

            # Debug response
            puts "API Response type: #{response.class}"
            puts "API Response content: #{response.inspect}"

            # Convert response to hash if it's not already
            response = response.to_hash if response.respond_to?(:to_hash)

            # Validate response structure
            unless response.is_a?(Hash)
              error("Invalid response format from API. Expected Hash, got: #{response.class}. Response: #{response.inspect}")
            end

            unless response.key?('data')
              error("Invalid response format from API. Missing 'data' key. Response: #{response.inspect}")
            end

            # Check if we found any results
            if response['data'].nil? || response['data'].empty?
              error("No vendor found matching name: '#{vendor_name}'. Please verify the vendor name and try again.")
            end

            # If multiple results found, handle exact matches
            if response['data'].length > 1
              # Find exact name matches
              exact_matches = response['data'].select { |vendor| vendor.dig('attributes', 'name') == vendor_name }
              
              # Error if multiple exact matches
              if exact_matches.length > 1
                matching_vendors = exact_matches.map { |v| "#{v.dig('attributes', 'name')} (ID: #{v['id']})" }
                error("Multiple vendors found with exact name '#{vendor_name}':\n#{matching_vendors.join("\n")}\nPlease use Vendor ID for exact match.")
              end
              
              # If we have one exact match, return it
              if exact_matches.length == 1
                puts "Found exact name match: #{exact_matches.first['id']}"
                return exact_matches.first
              end
              
              # If we have partial matches but no exact match, error
              matching_vendors = response['data'].map { |v| "#{v.dig('attributes', 'name')} (ID: #{v['id']})" }
              error("Multiple vendors found with similar name '#{vendor_name}':\n#{matching_vendors.join("\n")}\nPlease use Vendor ID for exact match.")
            end

            # Return the single match
            puts "Returning match: #{response['data'].first['id']}"
            response['data'].first
          rescue => e
            error("Unexpected error while searching for vendor: #{e.message}\nBacktrace: #{e.backtrace.join("\n")}")
          end
        end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['vendor']
      end,

      sample_output: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Get a sample vendor
        response = get("/#{account_slug}/v1/vendors")
                    .params(limit: 1)
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |_code, body, _header, message|
                      error("Failed to fetch sample vendor: #{message}: #{body}")
                    end

        response['data'].first || {}
      end
    },

    list_vendors: {
      title: "List Vendors",
      subtitle: "List vendors from ScopeStack",
      description: "List <span class='provider'>vendors</span> from <span class='provider'>ScopeStack</span>",
      help: "Retrieves a list of all vendors with optional filters for active status and name.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "active",
            label: "Active Status",
            type: "boolean",
            control_type: "checkbox",
            hint: "Filter by active status. Checked for active vendors, unchecked for inactive vendors.",
            optional: true,
            default: true
          },
          {
            name: "name",
            label: "Vendor Name",
            type: "string",
            control_type: "text",
            hint: "Filter by vendor name (partial match)",
            optional: true
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Build filter parameters
        filter_params = {}
        filter_params['filter[active]'] = input['active'] if input['active'].present?
        filter_params['filter[name]'] = input['name'] if input['name'].present?

        # Set a reasonable page size for each request
        filter_params["page[size]"] = 100

        all_data = []
        current_page = 1
        has_more_pages = true

        while has_more_pages
          filter_params["page[number]"] = current_page
          
          response = get("/#{account_slug}/v1/vendors")
            .params(filter_params)
            .headers('Accept': 'application/vnd.api+json')
            .after_error_response(/.*/) do |code, body, _header, message|
              case code
              when 400
                error("Invalid filter parameters. Please check your filter values: #{message}: #{body}")
              when 401, 403
                error("Authentication failed or insufficient permissions. Please check your credentials: #{message}")
              when 404
                error("Resource not found. Please check your account slug: #{message}")
              when 429
                error("Rate limit exceeded. Please try again later: #{message}")
              when 500..599
                error("ScopeStack server error occurred. Please try again later: #{message}")
              else
                error("Failed to fetch vendors (#{code}): #{message}: #{body}")
              end
            end
          
          # Add the current page's data to our collection
          all_data.concat(response['data'] || [])

          # Check if there are more pages
          total_pages = response.dig('meta', 'page-count') || 1
          has_more_pages = current_page < total_pages
          current_page += 1
        end

        # Return the combined data
        {
          data: all_data,
          meta: {
            total_count: all_data.size
          }
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: 'data',
            label: 'Vendors',
            type: 'array',
            of: 'object',
            properties: object_definitions['vendor']
          },
          {
            name: 'meta',
            label: 'Metadata',
            type: 'object',
            properties: [
              { 
                name: 'total_count',
                label: 'Total Count',
                type: 'integer'
              }
            ]
          }
        ]
      end,

      sample_output: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Get a sample vendor
        response = get("/#{account_slug}/v1/vendors")
                    .params(limit: 1)
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |_code, body, _header, message|
                      error("Failed to fetch sample vendor: #{message}: #{body}")
                    end

        {
          data: response['data'] || [],
          meta: {
            total_count: response.dig('meta', 'total_count') || 1
          }
        }
      end
    },

    create_or_update_vendor: {
      title: "Create or Update Vendor",
      subtitle: "Create a new vendor or update an existing one in ScopeStack",
      description: "Create or update <span class='provider'>vendor</span> in <span class='provider'>ScopeStack</span>",
      help: "This action creates a new vendor or updates an existing one. If a vendor ID is provided, it will attempt to update that specific vendor. If the vendor is not found, it will error out. If no vendor ID is provided, it will search for an existing vendor by name and update it if found, or create a new vendor if not found.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "vendor_id",
            label: "Vendor ID",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "If provided, updates the existing vendor. If the vendor is not found, the action will fail. If not provided, creates a new vendor or updates existing vendor by name."
          },
          {
            name: "name",
            label: "Vendor Name",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "Name of the vendor. Required for creation if no vendor ID is provided."
          },
          {
            name: "street_address",
            label: "Street Address",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "Street address of the vendor"
          },
          {
            name: "street2",
            label: "Street Address 2",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "Additional street address information"
          },
          {
            name: "city",
            label: "City",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "City where the vendor is located"
          },
          {
            name: "state",
            label: "State/Province",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "State or province where the vendor is located"
          },
          {
            name: "postal_code",
            label: "Postal Code",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "Postal code of the vendor"
          },
          {
            name: "country",
            label: "Country",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "Country where the vendor is located (e.g., 'us', 'gb')"
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        account_id = account_info[:account_id]

        # Validate that at least name is provided for creation
        if !input['vendor_id'].present? && !input['name'].present?
          error("Vendor name is required for creation if no vendor ID is provided.")
        end

        # If we have a vendor ID, update the existing vendor
        if input['vendor_id'].present?
          # Check if vendor exists
          response = get("/#{account_slug}/v1/vendors/#{input['vendor_id']}")
                     .headers('Accept': 'application/vnd.api+json')
                     .after_error_response(/.*/) do |code, body, _header, message|
                       case code
                       when 404
                         error("Vendor with ID '#{input['vendor_id']}' not found. Please verify the vendor ID.")
                       when 401, 403
                         error("Authentication failed or insufficient permissions. Please check your credentials: #{message}")
                       when 500..599
                         error("ScopeStack server error occurred. Please try again later: #{message}")
                       else
                         error("Failed to find vendor: #{message}: #{body}")
                       end
                     end

          # Prepare the update payload
          payload = {
            data: {
              type: "vendors",
              id: input['vendor_id'],
              attributes: {}
            }
          }

          # Add attributes if provided
          payload[:data][:attributes]["name"] = input['name'] if input['name'].present?
          payload[:data][:attributes]["street-address"] = input['street_address'] if input['street_address'].present?
          payload[:data][:attributes]["street2"] = input['street2'] if input['street2'].present?
          payload[:data][:attributes]["city"] = input['city'] if input['city'].present?
          payload[:data][:attributes]["state"] = input['state'] if input['state'].present?
          payload[:data][:attributes]["postal-code"] = input['postal_code'] if input['postal_code'].present?
          payload[:data][:attributes]["country"] = input['country'] if input['country'].present?

          # Update the existing vendor
          response = patch("/#{account_slug}/v1/vendors/#{input['vendor_id']}")
                     .payload(payload)
                     .headers('Accept': 'application/vnd.api+json',
                             'Content-Type': 'application/vnd.api+json')
                     .after_error_response(/.*/) do |code, body, _header, message|
                       case code
                       when 400
                         error("Invalid vendor data. Please check your input values: #{message}: #{body}")
                       when 401, 403
                         error("Authentication failed or insufficient permissions. Please check your credentials: #{message}")
                       when 404
                         error("Vendor not found. Please verify the vendor ID: #{message}")
                       when 500..599
                         error("ScopeStack server error occurred. Please try again later: #{message}")
                       else
                         error("Failed to update vendor: #{message}: #{body}")
                       end
                     end
        else
          # Search for existing vendor with the same name
          search_response = get("/#{account_slug}/v1/vendors")
                           .params(filter: { name: input['name'] })
                           .headers('Accept': 'application/vnd.api+json')
                           .after_error_response(/.*/) do |code, body, _header, message|
                             case code
                             when 400
                               error("Invalid search parameters. Please check the vendor name: #{message}: #{body}")
                             when 401, 403
                               error("Authentication failed or insufficient permissions. Please check your credentials: #{message}")
                             when 404
                               error("Resource not found. Please check your account slug: #{message}")
                             when 500..599
                               error("ScopeStack server error occurred. Please try again later: #{message}")
                             else
                               error("Failed to search for vendor: #{message}: #{body}")
                             end
                           end

          # If we found an existing vendor, update it
          if search_response['data']&.any?
            # Check if multiple vendors found with the same name
            if search_response['data'].length > 1
              matching_vendors = search_response['data'].map { |v| "#{v.dig('attributes', 'name')} (ID: #{v['id']})" }
              error("Multiple vendors found with name '#{input['name']}':\n#{matching_vendors.join("\n")}\nPlease use Vendor ID for exact match.")
            end

            existing_vendor = search_response['data'].first
            vendor_id = existing_vendor['id']

            # Prepare the update payload
            payload = {
              data: {
                type: "vendors",
                id: vendor_id,
                attributes: {}
              }
            }

            # Add attributes if provided
            payload[:data][:attributes]["name"] = input['name'] if input['name'].present?
            payload[:data][:attributes]["street-address"] = input['street_address'] if input['street_address'].present?
            payload[:data][:attributes]["street2"] = input['street2'] if input['street2'].present?
            payload[:data][:attributes]["city"] = input['city'] if input['city'].present?
            payload[:data][:attributes]["state"] = input['state'] if input['state'].present?
            payload[:data][:attributes]["postal-code"] = input['postal_code'] if input['postal_code'].present?
            payload[:data][:attributes]["country"] = input['country'] if input['country'].present?

            # Update the existing vendor
            response = patch("/#{account_slug}/v1/vendors/#{vendor_id}")
                       .payload(payload)
                       .headers('Accept': 'application/vnd.api+json',
                               'Content-Type': 'application/vnd.api+json')
                       .after_error_response(/.*/) do |code, body, _header, message|
                         case code
                         when 400
                           error("Invalid vendor data. Please check your input values: #{message}: #{body}")
                         when 401, 403
                           error("Authentication failed or insufficient permissions. Please check your credentials: #{message}")
                         when 404
                           error("Vendor not found. Please verify the vendor ID: #{message}")
                         when 500..599
                           error("ScopeStack server error occurred. Please try again later: #{message}")
                         else
                           error("Failed to update existing vendor: #{message}: #{body}")
                         end
                       end
          else
            # No existing vendor found, create a new one
            payload = {
              data: {
                type: "vendors",
                attributes: {},
                relationships: {
                  account: {
                    data: {
                      id: account_id,
                      type: "accounts"
                    }
                  }
                }
              }
            }

            # Add attributes if provided
            payload[:data][:attributes]["name"] = input['name'] if input['name'].present?
            payload[:data][:attributes]["active"] = true  # Always set to active for new vendors
            payload[:data][:attributes]["street-address"] = input['street_address'] if input['street_address'].present?
            payload[:data][:attributes]["street2"] = input['street2'] if input['street2'].present?
            payload[:data][:attributes]["city"] = input['city'] if input['city'].present?
            payload[:data][:attributes]["state"] = input['state'] if input['state'].present?
            payload[:data][:attributes]["postal-code"] = input['postal_code'] if input['postal_code'].present?
            payload[:data][:attributes]["country"] = input['country'] if input['country'].present?

            response = post("/#{account_slug}/v1/vendors")
                       .payload(payload)
                       .headers('Accept': 'application/vnd.api+json',
                               'Content-Type': 'application/vnd.api+json')
                       .after_error_response(/.*/) do |code, body, _header, message|
                         case code
                         when 400
                           error("Invalid vendor data. Please check your input values: #{message}: #{body}")
                         when 401, 403
                           error("Authentication failed or insufficient permissions. Please check your credentials: #{message}")
                         when 422
                           error("Validation error. Please check your input data: #{message}: #{body}")
                         when 500..599
                           error("ScopeStack server error occurred. Please try again later: #{message}")
                         else
                           error("Failed to create vendor: #{message}: #{body}")
                         end
                       end
          end
        end

        response
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['vendor']
      end,

      sample_output: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Get a sample vendor
        response = get("/#{account_slug}/v1/vendors")
                    .params(limit: 1)
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |_code, body, _header, message|
                      error("Failed to fetch sample vendor: #{message}: #{body}")
                    end

        response['data'].first || {}
      end
    },
    
    create_or_update_crm_opportunity: {
      title: "Create or Update CRM Opportunity",
      subtitle: "Creates a new CRM opportunity or updates an existing one in ScopeStack based on matching criteria",
      description: lambda do |input|
        "Create a new opportunity or update an existing one in <span class='provider'>ScopeStack</span>. " \
        "The action first attempts to update using a ScopeStack ID if provided. " \
        "If no ID is provided, it searches for a match using the foreign CRM opportunity ID."
      end,
      help: {
        body: "This action creates or updates a CRM opportunity in ScopeStack using the following logic:\n\n" \
              "1. If a ScopeStack opportunity ID is provided:\n" \
              "   - Attempts to update that specific opportunity\n" \
              "   - Returns an error if the opportunity is not found\n\n" \
              "2. If no ScopeStack ID is provided:\n" \
              "   - Searches for an existing opportunity using the foreign CRM opportunity ID\n" \
              "   - If exactly one match is found, updates that opportunity\n" \
              "   - If multiple matches are found, returns an error\n" \
              "   - If no match is found, creates a new opportunity\n\n" \
              "This ensures that opportunities are properly synchronized between your CRM system and ScopeStack.",
        learn_more_url: "https://docs.scopestack.io/api/#tag/CRM-Opportunities",
        learn_more_text: "CRM Opportunities API Documentation"
      },
    
      # 1) Build input fields dynamically
      input_fields: lambda do |object_definitions, connection|
        # A) Get static fields from the object definition
        fields = object_definitions["crm_opportunity"]
    
        # B) Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
    
        # C) Fetch dynamic project variables
        variables_response = get("/#{account_slug}/v1/project-variables")
                             .params(filter: { 'variable-context': 'crm_opportunity' })
                            .headers('Accept': 'application/vnd.api+json')
                            .after_error_response(/.*/) do |_code, body, _header, message|
                               error("Failed to fetch CRM opportunity variables: #{message}: #{body}")
                             end
    
        # D) Append dynamic fields to the input schema
        if variables_response["data"].is_a?(Array)
          variables_response["data"].each do |var|
            attrs = var["attributes"]
            field = {
              name: "var_#{attrs['name']}",
              label: attrs['label'],
              optional: !attrs['required'],
              hint: "CRM opportunity variable: #{attrs['label']}"
            }
    
            case attrs['variable-type']
            when 'number'
              field[:type] = 'number'
              field[:control_type] = 'number'
              if attrs['minimum'].present? || attrs['maximum'].present?
                range_text = []
                range_text << "min: #{attrs['minimum']}" if attrs['minimum'].present?
                range_text << "max: #{attrs['maximum']}" if attrs['maximum'].present?
                field[:hint] = "#{field[:hint]} (#{range_text.join(', ')})"
              end
            when 'date'
              field[:type] = 'date'
              field[:control_type] = 'date'
            when 'text'
              field[:type] = 'string'
              if attrs['select-options'].present?
                field[:control_type] = 'select'
                field[:pick_list] = attrs['select-options'].map { |opt| [opt['key'], opt['value']] }
                field[:toggle_hint] = 'Select from list'
                field[:toggle_field] = {
                  name: field[:name],
                  label: field[:label],
                  type: 'string',
                  control_type: 'text',
                  optional: field[:optional],
                  toggle_hint: 'Use custom value'
                }
                
                # Find and set default option if one exists
                default_option = attrs['select-options'].find do |opt|
                  opt['default'] == true || opt['default'] == 'true' || opt['default'].present?
                end
                field[:default] = default_option['key'] if default_option
              else
                field[:control_type] = 'text'
              end
            end
    
            fields << field
          end
        end
    
        fields
      end,
    
      # 2) Execute logic
      execute: lambda do |connection, input|
        puts "Starting create_or_update_crm_opportunity action"
        puts "Input received: #{input.inspect}"
    
        # A) Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        account_id = account_info[:account_id]
    
        puts "Account slug: #{account_slug}"
        puts "Account ID: #{account_id}"
    
        error("Account slug is required for this operation.") unless account_slug
        error("Account ID is required for this operation.")   unless account_id
    
        # B) Construct display name if no override
        display_name = if input["display-name-override"].present?
          input["display-name-override"]
        else
          "#{input["account-name"]} / #{input["name"]} / #{input["opportunity-id"]}"
        end
        puts "Using display name: #{display_name}"
    
        # C) Build the base payload (static fields)
              payload = {
          data: {
            type: "crm-opportunities",
            attributes: {
              "opportunity-id": input["opportunity-id"],
              "name":           input["name"],
              "display-name":   display_name,
              "amount":         input["amount"].present? ? input["amount"].to_s : nil,
              "stage":          input["stage"],
              "is-closed": input["is-closed"].present? ? input["is-closed"].to_s.downcase == "true" : false,
              "owner-id":       input["owner-id"],
              "owner-name":     input["owner-name"],
              "account-id":     input["account-id"],
              "account-name":   input["account-name"],
              "location-name":  input["location-name"],
              "street":         input["street"],
              "city":           input["city"],
              "state":          input["state"],
              "postal-code":    input["postal-code"],
              "country":        input["country"]
            },
            relationships: {
              account: {
                data: {
                  type: "accounts",
                  id:   account_id.to_s
                }
              }
            }
          }
        }
    
        # D) Gather dynamic fields from input (var_* => custom-attributes)
        custom_attributes = []
        input.each do |key, value|
          next if value.blank?
    
          if key.start_with?("var_")
            custom_attributes << {
              key: key.sub("var_", ""),
              val: value
            }
          end
        end
    
        if custom_attributes.present?
          puts "Adding custom attributes: #{custom_attributes.inspect}"
          payload[:data][:attributes]["custom-attributes"] = custom_attributes
        end
    
        # E) Add optional project relationship if present
        if input["project_id"].present?
          puts "Adding project relationship with ID: #{input["project_id"]}"
          payload[:data][:relationships][:projects] = {
            data: [{
              type: "projects",
              id:   input["project_id"]
            }]
          }
        end
    
        puts "Final payload structure: #{payload.inspect}"
        puts "Payload JSON: #{payload.to_json}"
    
        # F) Update or Create Logic
        if input["id"].present?
          # 1) If we have a ScopeStack ID => direct update
          puts "ScopeStack ID provided (#{input["id"]}), attempting direct update..."
          payload[:data][:id] = input["id"]
    
          response = patch("/#{account_slug}/v1/crm-opportunities/#{input['id']}")
                     .headers(
                       "Content-Type": "application/vnd.api+json",
                       "Accept":       "application/vnd.api+json"
                     )
                     .payload(payload)
                     .after_error_response(/.*/) do |code, body, header, message|
                       puts "Error response details:"
                       puts "Status code: #{code}"
                       puts "Headers: #{header.inspect}"
                       puts "Body: #{body}"
                       error("Failed to update opportunity with ScopeStack ID #{input['id']}: #{message}: #{body}")
                     end
          puts "Successfully updated opportunity with ScopeStack ID"
          response
        else
          # 2) No ScopeStack ID => search by foreign CRM ID
          # First search for non-closed opportunities
          filter_params = { 
            "filter[opportunity-id]" => input["opportunity-id"],
            "filter[is-closed]" => "false"
          }

          puts "Searching for non-closed opportunities with filter: #{filter_params.inspect}"
          existing_opps = get("/#{account_slug}/v1/crm-opportunities")
                          .params(filter_params)
                          .headers("Accept": "application/vnd.api+json")
                          .after_error_response(/.*/) do |code, body, header, message|
                            puts "Error response details:"
                            puts "Status code: #{code}"
                            puts "Headers: #{header.inspect}"
                            puts "Body: #{body}"
                            error("Failed to search for opportunities: #{message}: #{body}")
                          end

          # If no matches found in non-closed state, search for closed opportunities
          if existing_opps["data"].empty?
            puts "No non-closed opportunities found, searching for closed opportunities..."
            filter_params["filter[is-closed]"] = "true"
            
            existing_opps = get("/#{account_slug}/v1/crm-opportunities")
                            .params(filter_params)
                            .headers("Accept": "application/vnd.api+json")
                            .after_error_response(/.*/) do |code, body, header, message|
                              puts "Error response details:"
                              puts "Status code: #{code}"
                              puts "Headers: #{header.inspect}"
                              puts "Body: #{body}"
                              error("Failed to search for opportunities: #{message}: #{body}")
                            end
          end

          puts "Search response: #{existing_opps.inspect}"
    
          if existing_opps["data"].length > 1
            error("Multiple opportunities found with foreign CRM ID #{input['opportunity-id']}. " \
                  "Provide a specific ScopeStack opportunity ID to update. Found IDs: #{existing_opps['data'].map { |opp| opp['id'] }.join(', ')}")
          elsif existing_opps["data"].length == 1
            # Update existing
            existing_id = existing_opps["data"][0]["id"]
            existing_record = existing_opps["data"][0]
            puts "Found matching opportunity with ScopeStack ID: #{existing_id}"
            
            # Preserve existing relationships
            if existing_record["relationships"].present?
              existing_record["relationships"].each do |rel_name, rel_data|
                if rel_data["data"].present?
                  payload[:data][:relationships][rel_name] = {
                    data: rel_data["data"]
                  }
                end
              end
            end
            
            # Preserve existing custom attributes
            if existing_record["attributes"]["custom-attributes"].present?
              existing_custom_attrs = existing_record["attributes"]["custom-attributes"]
              if custom_attributes.present?
                # Merge existing and new custom attributes
                existing_custom_attrs.each do |existing_attr|
                  unless custom_attributes.any? { |new_attr| new_attr[:key] == existing_attr["key"] }
                    custom_attributes << { key: existing_attr["key"], val: existing_attr["val"] }
                  end
                end
              else
                custom_attributes = existing_custom_attrs.map { |attr| { key: attr["key"], val: attr["val"] } }
              end
            end
            
            if custom_attributes.present?
              payload[:data][:attributes]["custom-attributes"] = custom_attributes
            end
            
            payload[:data][:id] = existing_id
            puts "Final update payload: #{payload.to_json}"

            response = patch("/#{account_slug}/v1/crm-opportunities/#{existing_id}")
                       .headers(
                         "Content-Type": "application/vnd.api+json",
                         "Accept":       "application/vnd.api+json"
                       )
                       .payload(payload)
                       .after_error_response(/.*/) do |code, body, header, message|
                         puts "Error response details:"
                         puts "Status code: #{code}"
                         puts "Headers: #{header.inspect}"
                         puts "Body: #{body}"
                         error("Failed to update matched opportunity: #{message}: #{body}")
                       end
            puts "Successfully updated existing opportunity matched by foreign CRM ID"
            response
          else
            # Create new if none found
            puts "No matching opportunity found, creating new opportunity..."
            response = post("/#{account_slug}/v1/crm-opportunities")
                       .headers(
                         "Content-Type": "application/vnd.api+json",
                         "Accept":       "application/vnd.api+json"
                       )
                       .payload(payload)
                       .after_error_response(/.*/) do |code, body, header, message|
                         puts "Error response details:"
                         puts "Status code: #{code}"
                         puts "Headers: #{header.inspect}"
                         puts "Body: #{body}"
                         error("Failed to create opportunity: #{message}: #{body}")
                       end
            puts "Successfully created new opportunity"
            response
          end
        end
      end,
    
      output_fields: lambda do |object_definitions|
        # Return standard CRM opportunity fields in output
        object_definitions["crm_opportunity"]
      end,
    
      sample_output: lambda do |_connection, _input|
        {
          "data" => {
            "id" => "123",
            "type" => "crm-opportunities",
            "attributes" => {
              "opportunity-id" => "OPP-123",
              "name" => "Sample Opportunity",
              "display-name" => "Sample Client / Sample Opportunity / OPP-123",
              "amount" => "10000.00",
              "stage" => "Proposal",
              "is-closed" => false,
              "owner-id" => "OWN-123",
              "owner-name" => "John Doe",
              "account-id" => "ACC-123",
              "account-name" => "Sample Client",
              "location-name" => "Main Office",
              "street" => "123 Main St",
              "city" => "San Francisco",
              "state" => "CA",
              "postal-code" => "94105",
              "country" => "US",
              "custom-attributes" => {
                "estimated_hours" => "40",
                "some_select_var" => "Option A"
              }
            },
            "relationships" => {
              "account" => {
                "data" => {
                  "type" => "accounts",
                  "id" => "ACC-123"
                }
              },
              "projects" => {
                "data" => [
                  {
                    "type" => "projects",
                    "id" => "PRJ-123"
                  }
                ]
              }
            }
          }
        }
      end
    },

    create_or_update_project: {
      title: "Create or Update Project",
      subtitle: "Create or update a project in ScopeStack",
      description: "Create or update <span class='provider'>project</span> in <span class='provider'>ScopeStack</span>",
      help: "This action creates a new project or updates an existing one in your ScopeStack instance. If a Project ID is provided, it will update the existing project. If no Project ID is provided, it will create a new project. You can optionally include a service location for the project.",

      input_fields: lambda do |object_definitions, connection|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        # Add Project ID field as the first field
        all_fields = [
          {
            name: "project_id",
            label: "Project ID",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "If provided, this will update an existing project. If left blank, a new project will be created."
          },
          {
            name: "project_details",
            label: "Project Details",
            type: "object",
            properties: [
              { 
                name: "project_name",
                label: "Project Name",
                type: "string",
                control_type: "text",
                optional: true,
                hint: "Name of the project. Required when creating a new project."
              },
              { 
                name: "presales_engineer_id",
                label: "Presales Engineer ID",
                type: "string",
                control_type: "text",
                optional: true,
                hint: "Direct ID of the presales engineer. If provided, this takes precedence over email."
              },
              {
                name: "presales_engineer_email",
                label: "Presales Engineer Email",
                type: "string",
                control_type: "email",
                optional: true,
                hint: "Email address of the presales engineer. Only used if ID is not provided.",
                render_input: lambda do |field|
                  field if input['project_details']['presales_engineer_id'].blank?
                end
              },
              { 
                name: "payment_term_id",
                label: "Payment Term ID",
                type: "string",
                control_type: "text",
                optional: true,
                hint: "Direct ID of the payment term. If not provided, the default payment term will be used."
              },
              { 
                name: "rate_table_id",
                label: "Rate Table ID",
                type: "integer",
                control_type: "number",
                optional: true,
                hint: "Direct ID of the rate table. If not provided, the default rate table will be used."
              },
              { 
                name: "msa_date",
                label: "MSA Date",
                type: "date",
                control_type: "date",
                optional: true
              }
            ]
          },
          {
            name: "tags",
            label: "Tags",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "Comma-separated list of tags to add to the project (e.g. tag1, tag2, tag3)"
          },
          {
            name: "client",
            label: "Client",
            type: "object",
            control_type: "section",
            optional: true,
            hint: "Client information for the project. Either provide a Client ID or Client Name. If only Name is provided, a new client will be created if one doesn't exist.",
            properties: [
              { 
                name: "id", 
                label: "Client ID",
                type: "string", 
                control_type: "text",
                optional: true,
                hint: "If provided, the project will be attached to this existing client"
              },
              { 
                name: "name",
                label: "Client Name",
                type: "string", 
                control_type: "text",
                optional: true,
                hint: "If provided without a Client ID, a new client will be created if one doesn't exist"
              },
              {
                name: "domain",
                label: "Domain",
                type: "string",
                control_type: "text",
                optional: true,
                hint: "Optional domain for the client"
              },
              {
                name: "msa_date",
                label: "MSA Date",
                type: "string",
                control_type: "date",
                optional: true,
                hint: "Optional MSA date for the client"
              }
            ]
          },
          {
            name: "sales_executive",
            label: "Sales Executive",
            type: "object",
            properties: [
              {
                name: "id",
                label: "Sales Executive ID",
                type: "string",
                control_type: "text",
                optional: true,
                hint: "Direct ID of the sales executive. If provided, this will be used to associate the sales executive with the project."
              },
              {
                name: "name",
                label: "Sales Executive Name",
                type: "string",
                control_type: "text",
                optional: true,
                hint: "Name of the sales executive. If ID is not provided, this will be used to search for an existing sales executive or create a new one."
              },
              {
                name: "email",
                label: "Sales Executive Email",
                type: "string",
                control_type: "email",
                optional: true,
                hint: "Email address of the sales executive. Optional field used when creating a new sales executive."
              },
              {
                name: "title",
                label: "Sales Executive Title",
                type: "string",
                control_type: "text",
                optional: true,
                hint: "Job title of the sales executive. Optional field used when creating a new sales executive."
              },
              {
                name: "phone",
                label: "Sales Executive Phone",
                type: "string",
                control_type: "phone",
                optional: true,
                hint: "Phone number of the sales executive. Optional field used when creating a new sales executive."
              }
            ]
          }
        ]
        
        # Fetch all project variables (both project and service location)
        project_variables_response = get("/#{account_slug}/v1/project-variables")
                                     .params(filter: { 'variable-context': 'project,service_location' })
                      .headers('Accept': 'application/vnd.api+json')
                      .after_error_response(/.*/) do |_code, body, _header, message|
                                       error("Failed to fetch project variables: #{message}: #{body}")
                                     end

        # Separate project and location variables
        project_vars = project_variables_response['data'].select { |v| v['attributes']['variable-context'] == 'project' }
        location_vars = project_variables_response['data'].select { |v| v['attributes']['variable-context'] == 'service_location' }
        
        # Helper function to create field based on variable type
        create_field = lambda do |var, is_location = false|
          prefix = is_location ? "location_var_" : "project_var_"
          field = {
            name: "#{prefix}#{var['attributes']['name']}",
            label: var['attributes']['label'],
            optional: !var['attributes']['required'],
            hint: "#{is_location ? 'Location' : 'Project'} variable: #{var['attributes']['label']}"
          }
          
          case var['attributes']['variable-type']
          when 'number'
            if var['attributes']['select-options'].present?
              field[:control_type] = 'select'
              field[:pick_list] = var['attributes']['select-options'].map { |opt| [opt['key'], opt['value']] }
              # Find and set default option if one exists
              default_option = var['attributes']['select-options'].find do |opt| 
                opt['default'] == true || opt['default'] == 'true' || opt['default'].present?
              end
              field[:default] = default_option['key'] if default_option
              field[:toggle_hint] = 'Select from list'
              field[:toggle_field] = {
                name: field[:name],
                label: field[:label],
                type: 'integer',
                control_type: 'number',
                optional: field[:optional],
                toggle_hint: 'Use custom value'
              }
            else
              field[:type] = 'integer'
              field[:control_type] = 'number'
              field[:min] = var['attributes']['minimum'] if var['attributes']['minimum'].present?
              field[:max] = var['attributes']['maximum'] if var['attributes']['maximum'].present?
              # Add min/max to hint if they exist
              if var['attributes']['minimum'].present? || var['attributes']['maximum'].present?
                range_text = []
                range_text << "minimum: #{var['attributes']['minimum']}" if var['attributes']['minimum'].present?
                range_text << "maximum: #{var['attributes']['maximum']}" if var['attributes']['maximum'].present?
                field[:hint] = "#{field[:hint]} (#{range_text.join(', ')})"
              end
            end
          when 'date'
            field[:type] = 'date'
            field[:control_type] = 'date'
          when 'text'
            field[:type] = 'string'
            if var['attributes']['select-options'].present?
              field[:control_type] = 'select'
              field[:pick_list] = var['attributes']['select-options'].map { |opt| [opt['key'], opt['value']] }
              # Find and set default option if one exists
              default_option = var['attributes']['select-options'].find do |opt| 
                opt['default'] == true || opt['default'] == 'true' || opt['default'].present?
              end
              field[:default] = default_option['key'] if default_option
              field[:toggle_hint] = 'Select from list'
              field[:toggle_field] = {
                name: field[:name],
                label: field[:label],
                type: 'string',
                control_type: 'text',
                optional: field[:optional],
                toggle_hint: 'Use custom value'
              }
            else
              field[:control_type] = 'text'
            end
          end
          
          field
        end

        # Conditionally add project variables section
        unless project_vars.empty?
          all_fields << {
            name: "project_variables",
            label: "Project Variables",
            type: "object",
            properties: project_vars.map { |var| create_field.call(var) }
          }
        end

        # Add the service location checkbox
        all_fields << {
          name: "include_service_location",
          label: "Include Service Location",
          control_type: "checkbox",
          type: "boolean", 
          optional: true,
          sticky: true,
          hint: "Check this box if you want to create a service location for this project"
        }

        # Build the location properties array
        location_properties = [
          { 
            name: "name", 
            label: "Location Name",
            type: "string", 
            control_type: "text",
            optional: true,
            hint: "Required if creating a service location"
          },
          { 
            name: "street",
            label: "Street",
            type: "string", 
            control_type: "text",
            optional: true,
            hint: "Required if creating a service location"
          },
          { 
            name: "street2",
            label: "Street 2",
            type: "string", 
            control_type: "text",
            optional: true 
          },
          { 
            name: "city",
            label: "City",
            type: "string", 
            control_type: "text",
            optional: true,
            hint: "Required if creating a service location"
          },
          { 
            name: "state",
            label: "State",
            type: "string", 
            control_type: "text",
            optional: true,
            hint: "Required if creating a service location"
          },
          { 
            name: "postal_code",
            label: "Postal Code",
            type: "string", 
            control_type: "text",
            optional: true,
            hint: "Required if creating a service location"
          },
          { 
            name: "country",
            label: "Country",
            type: "string",
            control_type: "text",
            optional: true 
          },
          { 
            name: "remote",
            label: "Remote",
            type: "boolean",
            control_type: "checkbox",
            optional: true 
          }
        ]

        # Conditionally add location variables section
        unless location_vars.empty?
          location_properties << {
            name: "location_variables",
            type: "object",
            properties: location_vars.map { |var| create_field.call(var, true) }
          }
        end

        # Add the main location object field
        all_fields << {
        name: "location",
        label: "Service Location Details",
        type: "object",
        properties: location_properties,
        optional: ->(input) { input['include_service_location'].to_s != 'true' },
        if: ->(input) { input['include_service_location'].to_s == 'true' }
      }

        # Return the complete list of fields
        all_fields
      end,

      execute: lambda do |connection, input|    
        # Get account information using the reusable method
          account_info = call('get_account_info', connection)
          account_slug = account_info[:account_slug]
          account_id = account_info[:account_id]

          # If this is an update, fetch the existing project data
          existing_project = nil
          if input['project_id'].present?
            existing_project = get("/#{account_slug}/v1/projects/#{input['project_id']}")
                                .headers('Accept': 'application/vnd.api+json')
                                .after_error_response(/.*/) do |_code, body, _header, message|
                                  error("Failed to fetch existing project: #{message}: #{body}")
                                end
            existing_project = existing_project['data']
          end
        
        # Validate project name for create operations
        if input['project_id'].blank? && input.dig('project_details', 'project_name').blank?
          error("Project Name is required when creating a new project.")
        end

        # Handle client lookup/creation
        client_id = nil
        if input['client'].present?
          # Try to find client by name first if no ID provided
          if input['client']['id'].blank? && input['client']['name'].present?
            client_response = get("/#{account_slug}/v1/clients")
                              .params(filter: { name: input['client']['name'] })
                              .headers('Accept': 'application/vnd.api+json')
                              .after_error_response(/.*/) do |_code, body, _header, message|
                                puts "Failed to find client by name: #{message}: #{body}"
                                nil
                              end

            if client_response && client_response['data'].present?
              client_id = client_response['data'].first['id']
            else
              # Create new client if not found
              client_payload = {
                data: {
                  type: "clients",
                  attributes: {
                    name: input['client']['name'],
                    domain: input['client']['domain'],
                    "msa-date": input['client']['msa_date']
                  }
                }
              }
              
              client_response = post("/#{account_slug}/v1/clients")
                                .headers('Content-Type': 'application/vnd.api+json',
                                        'Accept': 'application/vnd.api+json')
                                .payload(client_payload)
                                .after_error_response(/.*/) do |_code, body, _header, message|
                                  error("Failed to create client: #{message}: #{body}")
                                end
              client_id = client_response['data']['id']
            end
          elsif input['client']['id'].present?
            client_id = input['client']['id']
          end
        elsif existing_project.present?
          client_id = existing_project.dig('relationships', 'client', 'data', 'id')
        end

        # Only require client for new projects
        if input['project_id'].blank? && client_id.blank?
          error("Client is required when creating a new project.")
        end

        # Cache project variables at the start of execute block
        project_variables_cache = {}
        project_variables_response = get("/#{account_slug}/v1/project-variables")
                                    .params(filter: { 'variable-context': 'project,service_location' })
                                    .headers('Accept': 'application/vnd.api+json')
                                    .after_error_response(/.*/) do |_code, body, _header, message|
                                      puts "Failed to fetch project variables: #{message}: #{body}"
                                      nil
                                    end

        # Store in cache if response exists
        if project_variables_response
          project_variables_response['data'].each do |var|
            project_variables_cache[var['attributes']['name']] = var['attributes']
          end
        end

        # Create lookup for variable types
        variable_types = project_variables_response['data'].each_with_object({}) do |var, hash|
          hash[var['attributes']['name']] = var['attributes']
        end
        
        # Helper function to process variable value based on its type
        process_variable_value = lambda do |name, value|
          return nil if value.nil?
          var_attrs = variable_types[name]
          return value unless var_attrs  # Return as is if we don't have type info
          
          case var_attrs['variable-type']
          when 'number'
            if var_attrs['select-options'].present?
              # For number select fields, find the matching option value
              option = var_attrs['select-options'].find { |opt| opt['key'].to_s == value.to_s }
              option ? option['value'].to_i : value.to_i
            else
              value.to_i
            end
          when 'date'
            value.to_s  # Ensure date is sent as string
          when 'text'
            if var_attrs['select-options'].present?
              # For text select fields, find the matching option value
              option = var_attrs['select-options'].find { |opt| opt['key'].to_s == value.to_s }
              option ? option['value'].to_s : value.to_s
            else
              value.to_s
            end
          else
            value.to_s
          end
        end
        
        # Extract and process project variables from input
        project_variables = input['project_variables']&.keys
                               &.select { |k| k.start_with?('project_var_') }
                               &.map do |k|
                                 var_name = k.sub('project_var_', '')
                                 var_value = process_variable_value.call(var_name, input['project_variables'][k])
                                 { name: var_name, value: var_value }
                               end&.reject { |v| v[:value].nil? } || []
        
        # Handle sales executive
        sales_executive_id = nil
        sales_exec = input['sales_executive']

        if sales_exec.present?
          # If ID is provided, use it directly
          if sales_exec['id'].present?
            # Verify the sales executive exists
            response = get("/#{account_slug}/v1/sales-executives/#{sales_exec['id']}")
                        .headers('Accept': 'application/vnd.api+json')
                        .after_error_response(/.*/) do |_code, body, _header, message|
                          error("Failed to fetch sales executive: #{message}: #{body}")
                        end

            if response['data'].present?
              sales_executive_id = sales_exec['id']
            else
              error("Sales Executive with ID #{sales_exec['id']} not found")
            end
          # If name is provided but no ID, search for existing sales executive
          elsif sales_exec['name'].present?
          # Search by name
          response = get("/#{account_slug}/v1/sales-executives")
                        .params(filter: { name: sales_exec['name'], active: true })
                      .headers('Accept': 'application/vnd.api+json')
                      .after_error_response(/.*/) do |_code, body, _header, message|
                        error("Failed to fetch sales executives: #{message}: #{body}")
                      end
          
          if response['data'].any?
              # Use the first match if multiple found
              sales_executive_id = response['data'].first['id']
            else
              # Create new sales executive
            create_payload = {
                data: {
                  type: "sales-executives",
                  attributes: {
                    "name": sales_exec['name']
                  },
                  relationships: {
                    account: {
                      data: {
                        type: "accounts",
                        id: account_id.to_s
                      }
                    }
                  }
                }
              }

              # Add optional fields if provided
              create_payload[:data][:attributes]["email"] = sales_exec['email'] if sales_exec['email'].present?
              create_payload[:data][:attributes]["title"] = sales_exec['title'] if sales_exec['title'].present?
              create_payload[:data][:attributes]["phone"] = sales_exec['phone'] if sales_exec['phone'].present?
            
            create_response = post("/#{account_slug}/v1/sales-executives")
                          .headers('Content-Type': 'application/vnd.api+json',
                                  'Accept': 'application/vnd.api+json')
                              .payload(create_payload)
                          .after_error_response(/.*/) do |_code, body, _header, message|
                            error("Failed to create sales executive: #{message}: #{body}")
                          end
            
              sales_executive_id = create_response['data']['id']
            end
          end
        end
        
        # Handle presales engineer lookup
        presales_engineer_id = nil
        if input.dig('project_details', 'presales_engineer_id').present?
          presales_engineer_id = input.dig('project_details', 'presales_engineer_id')
        elsif input.dig('project_details', 'presales_engineer_email').present?
          # Validate email format
          email = input.dig('project_details', 'presales_engineer_email').strip
          unless email =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
            error("Invalid email format: #{email}")
          end

          # Search by email
          response = get("/#{account_slug}/v1/presales-engineers")
                      .params(filter: { email: email })
                      .headers('Accept': 'application/vnd.api+json')
                      .after_error_response(/.*/) do |_code, body, _header, message|
                        error("Failed to fetch presales engineer: #{message}: #{body}")
                      end

          if response['data'].any?
            presales_engineer_id = response['data'].first['id']
          end
        elsif existing_project.present?
          # Use existing presales engineer if no new one provided
          presales_engineer_id = existing_project.dig('relationships', 'presales-engineer', 'data', 'id')
        end
        
        # Handle payment term and rate table
        payment_term_id = nil
        rate_table_id = nil

        # First try to use provided IDs
        payment_term_id = input.dig('project_details', 'payment_term_id') if input.dig('project_details', 'payment_term_id').present?
        rate_table_id = input.dig('project_details', 'rate_table_id') if input.dig('project_details', 'rate_table_id').present?

        # If payment term ID not provided, try to get from existing project
        if payment_term_id.nil? && existing_project.present?
          payment_term_id = existing_project.dig('relationships', 'payment-term', 'data', 'id')
        end

        # If still no payment term ID, try to get default
        # Cache payment terms response at the start
        payment_terms_response = get("/#{account_slug}/v1/payment-terms")
                                .headers('Accept': 'application/vnd.api+json')
                                .after_error_response(/.*/) do |_code, body, _header, message|
                                  puts "Failed to fetch payment terms: #{message}: #{body}"
                                  nil
                                end

        # Find default term from cached response
        if payment_terms_response
          default_term = payment_terms_response['data'].find { |term| term['attributes']['default'] == true }
          payment_term_id = default_term['id'] if default_term
        end
        
        # Prepare the project payload
        project_payload = {
          data: {
            type: "projects",
            attributes: {
              "project-name": input.dig('project_details', 'project_name').presence || 
                            (existing_project&.dig('attributes', 'project-name') if input['project_id'].present?),
              "project-variables": project_variables
            },
            relationships: {
              account: {
                data: {
                  type: "accounts",
                  id: account_info[:account_id].to_s
                }
              }
            }
          }
        }

        # Only add client relationship if client_id exists
        if client_id.present?
          project_payload[:data][:relationships][:client] = {
            data: {
              type: "clients",
              id: client_id.to_s
            }
          }
        end
        
        # Handle sales executive
        sales_executive_id = nil
        sales_exec = input['sales_executive']

        if sales_exec.present?
          # If ID is provided, use it directly
          if sales_exec['id'].present?
            # Verify the sales executive exists
            response = get("/#{account_slug}/v1/sales-executives/#{sales_exec['id']}")
                        .headers('Accept': 'application/vnd.api+json')
                      .after_error_response(/.*/) do |_code, body, _header, message|
                          error("Failed to fetch sales executive: #{message}: #{body}")
                        end

            if response['data'].present?
              sales_executive_id = sales_exec['id']
            else
              error("Sales Executive with ID #{sales_exec['id']} not found")
            end
          # If name is provided but no ID, search for existing sales executive
          elsif sales_exec['name'].present?
            # Search by name
            response = get("/#{account_slug}/v1/sales-executives")
                        .params(filter: { name: sales_exec['name'], active: true })
                            .headers('Accept': 'application/vnd.api+json')
                            .after_error_response(/.*/) do |_code, body, _header, message|
                          error("Failed to fetch sales executives: #{message}: #{body}")
                        end

            if response['data'].any?
              # Use the first match if multiple found
              sales_executive_id = response['data'].first['id']
            else
              # Create new sales executive
              create_payload = {
                data: {
                  type: "sales-executives",
                  attributes: {
                    "active": true,
                    "name": sales_exec['name']
                  },
                  relationships: {
                    account: {
                      data: {
                        type: "accounts",
                        id: account_id.to_s
                      }
                    }
                  }
                }
              }

              # Add optional fields if provided
              create_payload[:data][:attributes]["email"] = sales_exec['email'] if sales_exec['email'].present?
              create_payload[:data][:attributes]["title"] = sales_exec['title'] if sales_exec['title'].present?
              create_payload[:data][:attributes]["phone"] = sales_exec['phone'] if sales_exec['phone'].present?

              create_response = post("/#{account_slug}/v1/sales-executives")
                          .headers('Content-Type': 'application/vnd.api+json',
                                  'Accept': 'application/vnd.api+json')
                                .payload(create_payload)
                          .after_error_response(/.*/) do |_code, body, _header, message|
                            error("Failed to create sales executive: #{message}: #{body}")
                          end

              sales_executive_id = create_response['data']['id']
            end
          end
        end

        # Add sales executive relationship if found or created
        if sales_executive_id.present?
          project_payload[:data][:relationships]['sales-executive'] = {
            data: {
              type: "sales-executives",
              id: sales_executive_id.to_s
            }
          }
        end
        
        if presales_engineer_id.present?
          project_payload[:data][:relationships]['presales-engineer'] = {
            data: {
              type: "presales-engineers",
              id: presales_engineer_id.to_s
            }
          }
        end
        
        # Handle payment term and rate table
        payment_term_id = nil
        rate_table_id = nil

        # First try to use provided IDs
        payment_term_id = input.dig('project_details', 'payment_term_id') if input.dig('project_details', 'payment_term_id').present?
        rate_table_id = input.dig('project_details', 'rate_table_id') if input.dig('project_details', 'rate_table_id').present?

        # If payment term ID not provided, try to get default
        if payment_term_id.nil?
          begin
            payment_terms_response = get("/#{account_slug}/v1/payment-terms")
                            .headers('Accept': 'application/vnd.api+json')
                            .after_error_response(/.*/) do |_code, body, _header, message|
                                       puts "Failed to fetch payment terms: #{message}: #{body}"
                                       nil
                                     end

            if payment_terms_response
              default_term = payment_terms_response['data'].find { |term| term['attributes']['default'] == true }
              payment_term_id = default_term['id'] if default_term
            end
          rescue => e
            puts "Error fetching default payment term: #{e.message}"
          end
        end

        # If rate table ID not provided, try to get default from client
        if rate_table_id.nil?
          begin
            client_response = get("/#{account_slug}/v1/clients/#{input.dig('project_details', 'client_id')}")
                              .headers('Accept': 'application/vnd.api+json')
                              .after_error_response(/.*/) do |_code, body, _header, message|
                                puts "Failed to fetch client: #{message}: #{body}"
                                nil
                              end

            if client_response && client_response.dig('data', 'relationships', 'rate-table', 'data', 'id')
              rate_table_id = client_response.dig('data', 'relationships', 'rate-table', 'data', 'id').to_s
            end
          rescue => e
            puts "Error fetching client rate table: #{e.message}"
          end
        end

        # Add payment term relationship if found
        if payment_term_id.present?
          project_payload[:data][:relationships]['payment-term'] = {
                data: {
              type: "payment-terms",
              id: payment_term_id.to_s
            }
          }
        end

        # Add rate table relationship if found
        if rate_table_id.present?
          project_payload[:data][:relationships]['rate-table'] = {
            data: {
              type: "rate-tables",
              id: rate_table_id.to_s
            }
          }
        end
        
        # Add MSA date if provided
        if input.dig('project_details', 'msa_date').present?
          project_payload[:data][:attributes]['msa-date'] = input.dig('project_details', 'msa_date')
        end
        
        # Add tag-list if tags are provided
        if input['tags'].present?
          tags_array = input['tags'].split(',').map(&:strip).reject(&:blank?)
          project_payload[:data][:attributes]['tag-list'] = tags_array
        end
        
        # Create or update the project based on project_id
        if input['project_id'].present?
          # Update existing project
          project_payload[:data][:id] = input['project_id']
          project_response = patch("/#{account_slug}/v1/projects/#{input['project_id']}")
                      .headers('Content-Type': 'application/vnd.api+json',
                              'Accept': 'application/vnd.api+json')
                             .payload(project_payload)
                             .after_error_response(/.*/) do |_code, body, _header, message|
                               error("Failed to update project: #{message}: #{body}")
                             end
        else
          # Create new project
        project_response = post("/#{account_slug}/v1/projects")
                             .headers('Content-Type': 'application/vnd.api+json',
                                     'Accept': 'application/vnd.api+json')
                           .payload(project_payload)
                           .after_error_response(/.*/) do |_code, body, _header, message|
                             error("Failed to create project: #{message}: #{body}")
                             end
                           end
        
                  project = project_response['data']
        
        # Create location if include_service_location is true
        if input['include_service_location'].to_s == 'true'
          # Validate required location fields
          required_location_fields = ['name', 'street', 'city', 'state', 'postal_code']
          missing_fields = required_location_fields.select { |f| input.dig('location', f).blank? }
          
          if missing_fields.any?
            error("The following location fields are required when creating a service location: #{missing_fields.join(', ')}")
          end
          
          # Extract and process location variables
          location_variables = input.dig('location', 'location_variables')&.keys
                                  &.select { |k| k.start_with?('location_var_') }
                                  &.map do |k|
                                    var_name = k.sub('location_var_', '')
                                    var_value = process_variable_value.call(var_name, input.dig('location', 'location_variables', k))
                                    { name: var_name, value: var_value }
                                  end&.reject { |v| v[:value].nil? } || []
          
          # Check for required location variables
          required_location_vars = project_variables_response['data']
                                   .select { |v| v['attributes']['variable-context'] == 'service_location' && v['attributes']['required'] }
          
          missing_vars = required_location_vars.reject do |var|
            location_variables.any? { |v| v[:name] == var['attributes']['name'] }
          end
          
          if missing_vars.any?
            error("The following location variables are required: #{missing_vars.map { |v| v['attributes']['label'] }.join(', ')}")
          end
          
          location_payload = {
            data: {
              type: "project-locations",
              attributes: {
                name: input['location']['name'],
                street: input['location']['street'],
                street2: input['location']['street2'],
                city: input['location']['city'],
                state: input['location']['state'],
                "postal-code": input['location']['postal_code'],
                country: input['location']['country'],
                remote: input['location']['remote'] == true,
                "project-variables": location_variables
              },
              relationships: {
                project: {
                  data: {
                    type: "projects",
                    id: project['id'].to_s
                  }
                }
              }
            }
          }
          
          location_response = post("/#{account_slug}/v1/project-locations")
                              .headers('Content-Type': 'application/vnd.api+json')
                              .payload(location_payload)
                              .after_error_response(/.*/) do |_code, body, _header, message|
                                error("Failed to create project location: #{message}: #{body}")
                              end
          
          # Add location to project response
          project['location'] = location_response['data']
        end
        
        project
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['project'].concat([
          { name: "location", type: "object", properties: object_definitions['project_location'] }
        ])
      end,

      sample_output: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        # Get a sample project
        projects_response = get("/#{account_slug}/v1/projects")
                              .params(limit: 1)
                              .headers('Accept': 'application/vnd.api+json')
                              .after_error_response(/.*/) do |_code, body, _header, message|
                                error("Failed to fetch sample project: #{message}: #{body}")
                              end
        
        # Return the first project or an empty hash if none found
        projects_response['data'].first || {}
      end
    },

    delete_crm_opportunity: {
      title: "Delete CRM Opportunity",
      subtitle: "Delete CRM opportunity by ScopeStack ID or Foreign CRM ID",
      description: "Delete <span class='provider'>CRM opportunity</span> in <span class='provider'>ScopeStack</span>",
      help: {
        body: "Deletes one or more CRM opportunities. You can delete by either:\n" \
              "1. ScopeStack ID - Deletes a single specific opportunity\n" \
              "2. Foreign CRM ID - Deletes all opportunities that match this external ID\n\n" \
              "At least one of these IDs must be provided. If both are provided, " \
              "the ScopeStack ID takes precedence."
      },

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "id",
            label: "ScopeStack Opportunity ID",
            type: "string",
            optional: true,
            hint: "Internal ScopeStack ID of the opportunity to delete"
          },
          {
            name: "opportunity_id",
            label: "Foreign CRM ID",
            type: "string",
            optional: true,
            hint: "External CRM ID of the opportunity(ies) to delete. All matches will be deleted."
          }
        ]
      end,

      execute: lambda do |connection, input|
        # 1) Get account_slug
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # 2) Validate presence of at least one ID
        if input["id"].blank? && input["opportunity_id"].blank?
          error("Either a ScopeStack ID or a Foreign CRM ID must be provided.")
        end

        # 3a) Delete by ScopeStack ID if present
        if input["id"].present?
          puts "Deleting opportunity with ScopeStack ID: #{input['id']}"

          begin
            response = delete("/#{account_slug}/v1/crm-opportunities/#{input['id']}")
                        .headers("Accept": "application/vnd.api+json")
                        .after_error_response(/.*/) do |_code, body, _header, message|
                          error("Failed to delete opportunity: #{message}: #{body}")
                        end

            {
              success: true,
              message: "Opportunity with ScopeStack ID #{input['id']} deleted successfully.",
              response: response
            }
          rescue => e
            error("Failed to delete opportunity: #{e.message}")
          end
        else
          # 3b) Otherwise, delete all matching the foreign CRM ID
          puts "Searching for opportunities with foreign CRM ID: #{input['opportunity_id']}"

          begin
            opportunities = get("/#{account_slug}/v1/crm-opportunities")
                            .params("filter[opportunity-id]": input["opportunity_id"])
                            .headers("Accept": "application/vnd.api+json")
                            .after_error_response(/.*/) do |_code, body, _header, message|
                              error("Failed to search opportunities: #{message}: #{body}")
                            end

            opp_data = opportunities["data"].is_a?(Array) ? opportunities["data"] : []
            if opp_data.empty?
              error("No opportunities found with foreign CRM ID: #{input['opportunity_id']}")
            end

            deleted_count = 0
            failed_deletions = []

            opp_data.each do |opp|
              puts "Deleting opportunity with ScopeStack ID: #{opp['id']}"

              begin
                response = delete("/#{account_slug}/v1/crm-opportunities/#{opp['id']}")
                            .headers("Accept": "application/vnd.api+json")
                            .after_error_response(/.*/) do |_code, body, _header, message|
                              error("Failed to delete opportunity #{opp['id']}: #{message}: #{body}")
                            end
                deleted_count += 1
              rescue => e
                failed_deletions << { id: opp['id'], error: e.message }
              end
            end

            {
              success: true,
              message: "Successfully deleted #{deleted_count} opportunity(ies) with foreign CRM ID: #{input['opportunity_id']}",
              deleted_count: deleted_count,
              failed_deletions: failed_deletions
            }
          rescue => e
            error("Failed to process opportunities: #{e.message}")
          end
        end
      end
    },

    get_presales_engineer: {
      title: "Get Presales Engineer",
      subtitle: "Find a presales engineer in ScopeStack",
      description: "Find <span class='provider'>presales engineer</span> in <span class='provider'>ScopeStack</span>",
      help: "Finds a presales engineer using either ID or Email. If both are provided, ID takes precedence.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "engineer_id",
            label: "Engineer ID",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "The unique identifier of the presales engineer. If provided, this will be used to find the engineer. If not provided, Email will be used instead."
          },
          {
            name: "email",
            label: "Email",
            type: "string",
            control_type: "email",
            optional: true,
            hint: "The email address of the presales engineer. This will be used to find the engineer if ID is not provided."
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Validate that at least one identifier is provided
        if input['engineer_id'].blank? && input['email'].blank?
          error("Either Engineer ID or Email must be provided to find the presales engineer.")
        end

        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Determine which identifier to use
        if input['engineer_id'].present?
          # Search by ID
          response = get("/#{account_slug}/v1/presales-engineers/#{input['engineer_id']}")
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |_code, body, _header, message|
                        error("Failed to fetch presales engineer by ID: #{message}: #{body}")
                    end
        else
          # Validate email format
          email = input['email'].strip
          unless email =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
            error("Invalid email format: #{email}")
          end

          # Search by email
          response = get("/#{account_slug}/v1/presales-engineers")
                      .params("filter[email]": email)
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |_code, body, _header, message|
                        error("Failed to fetch presales engineer by email: #{message}: #{body}")
                    end

          # Check if we found any engineers
          if response['data'].empty?
            error("No presales engineer found with the email '#{email}'")
          end

          # Use the first matching engineer
          response = response['data'].first
        end

        response
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['presales_engineer']
      end
    },

    get_service_location: {
      title: "Get Service Location",
      subtitle: "Get a specific service location",
      description: "Get a specific <span class='provider'>service location</span> in <span class='provider'>ScopeStack</span>",
      help: "Retrieves a specific service location using its Location ID.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "location_id",
            label: "Location ID",
            type: "string",
            control_type: "text",
            optional: false,
            hint: "The ID of the service location to retrieve."
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Validate that at least one identifier is provided
        if input['location_id'].blank?
          error("Location ID must be provided to find the service location.")
        end

        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

          # Search by ID
          response = get("/#{account_slug}/v1/project-locations/#{input['location_id']}")
                    .params(include: 'project')
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |_code, body, _header, message|
                    error("Failed to fetch service location: #{message}: #{body}")
        end

        response['data']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['project_service_location']
      end
    },

    get_document_template: {
      title: "Get Document Template",
      subtitle: "Find a document template in ScopeStack",
      description: "Find <span class='provider'>document template</span> in <span class='provider'>ScopeStack</span>",
      help: {
        body: "Finds a document template by its exact name. The search is case-sensitive and will return the first matching template found.",
        learn_more_url: "https://docs.scopestack.io/api/v1/document-templates",
        learn_more_text: "Learn more about document templates"
      },

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "name",
            label: "Template Name",
            type: "string",
            control_type: "text",
            optional: false,
            hint: "Enter the exact name of the document template to find. The search is case-sensitive."
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        if input['name'].blank?
          error("Template name is required")
        end

        # Search by name
        response = get("/#{account_slug}/v1/document-templates")
                  .params(filter: { "name": input['name'] })
                  .headers('Accept': 'application/vnd.api+json')
                  .after_error_response(/.*/) do |_code, body, _header, message|
                    error("Failed to fetch document template: #{message}: #{body}")
                  end

        if response['data'].empty?
          error("No document template found with name: #{input['name']}")
        elsif response['data'].length > 1
          error("Multiple document templates found with name: #{input['name']}. Please ensure the template name is unique.")
        end
        response['data'].first
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['document_template']
      end,

      sample_output: lambda do |connection, input|
        {
          "id" => "1820",
          "type" => "document-templates",
          "links" => {
            "self" => "https://api.scopestack.io/scopestack-demo/v1/document-templates/1820"
          },
          "attributes" => {
            "active" => true,
            "name" => "PS+MS Template",
            "format" => "word_template",
            "merge-template-filename" => "ScopeStack-PSandMS_Template.docx",
            "merge-template" => "Sample template content",
            "filename-format" => [],
            "template-format" => "v1"
          },
          "relationships" => {
            "account" => {
              "links" => {
                "self" => "https://api.scopestack.io/scopestack-demo/v1/document-templates/1820/relationships/account",
                "related" => "https://api.scopestack.io/scopestack-demo/v1/document-templates/1820/account"
              }
            }
          }
        }
      end
    },

    create_project_document: {
      title: 'Create project document',
      subtitle: 'Creates a document from a template for a project',
      description: 'Creates a document from a template for a project in PDF or Word format',
      
      input_fields: lambda do |object_definitions|
        [
          {
            'name' => 'document_type',
            'label' => 'Document Type',
            'type' => 'string',
            'control_type' => 'select',
            'optional' => false,
            'pick_list' => [
              ['Document Template', 'sow'],
              ['Pricing', 'pricing'],
              ['Work Breakdown', 'breakdown']
            ],
            'hint' => 'Select the type of document to generate'
          },
          {
            'name' => 'project_id',
            'label' => 'Project ID',
            'type' => 'string',
            'control_type' => 'text',
            'optional' => false,
            'hint' => 'Enter the project ID'
          },
          {
            'name' => 'template_id',
            'label' => 'Template ID',
            'type' => 'string',
            'control_type' => 'text',
            'optional' => true,
            'hint' => 'Enter the template ID (required for Document Template)',
            'sticky' => true
          },
          {
            'name' => 'generate_pdf',
            'label' => 'Generate PDF',
            'type' => 'boolean',
            'control_type' => 'checkbox',
            'optional' => true,
            'default' => true,
            'hint' => 'Generate document as PDF (otherwise will be Word, Excel, or PowerPoint format). Note: This option only applies to Document Templates.'
          },
          {
            'name' => 'force_regeneration',
            'label' => 'Force regeneration',
            'type' => 'boolean',
            'control_type' => 'checkbox',
            'optional' => true,
            'default' => true,
            'hint' => 'Force generation of a new document even if one already exists'
          },

        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Validate template ID is provided for SOW documents
        if input['document_type'] == 'sow' && input['template_id'].blank?
          error('Template ID is required when creating a Document Template (SOW)')
        end

        # Determine template ID based on document type
        template_id = case input['document_type']
                     when 'pricing'
                       'pricing'
                     when 'breakdown'
                       'breakdown'
                     else
                       input['template_id']
                     end

        # Create document payload
        payload = {
          'data' => {
            'type' => 'project-documents',
            'attributes' => {
              'template-id' => template_id,
              'document-type' => input['document_type'],
              'force-regeneration' => input['force_regeneration'].to_s.downcase == 'true',
              'generate-pdf' => input['generate_pdf'].to_s.downcase == 'true'
            },
            'relationships' => {
              'project' => {
                'data' => {
                  'type' => 'projects',
                  'id' => input['project_id']
                }
              }
            }
          }
        }

        # Create document
        document_response = post("/#{account_slug}/v1/project-documents")
          .headers(
            'Accept' => 'application/vnd.api+json',
            'Content-Type' => 'application/vnd.api+json'
          )
                      .payload(payload)
                      .after_error_response(/.*/) do |_code, body, _header, message|
                     error("Failed to create document: #{message}: #{body}")
                   end

        document_id = document_response['data']['id']
        
        # Always wait for completion
        max_attempts = 60  # 5 minutes with 5 second intervals
        attempts = 0
        
        while attempts < max_attempts
          # Check document status
          status_response = get("/#{account_slug}/v1/project-documents/#{document_id}")
            .headers('Accept' => 'application/vnd.api+json')
            .after_error_response(/.*/) do |_code, body, _header, message|
              error("Failed to check document status: #{message}: #{body}")
            end
          
          status = status_response['data']['attributes']['status']
          
          if status == 'finished'
            return status_response['data']
          elsif status == 'error'
            error_text = status_response['data']['attributes']['error-text']
            error("Document generation failed: #{error_text}")
          end
          
          attempts += 1
          sleep(5) if attempts < max_attempts
        end
        
        error("Document generation timed out after 5 minutes")
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            'name' => 'id',
            'type' => 'string'
          },
          {
            'name' => 'type',
            'type' => 'string'
          },
          {
            'name' => 'attributes',
            'type' => 'object',
            'properties' => [
              {
                'name' => 'status',
                'type' => 'string'
              },
              {
                'name' => 'error-text',
                'type' => 'string'
              },
              {
                'name' => 'document-url',
                'type' => 'string'
              },
              {
                'name' => 'template-id',
                'type' => 'string'
              },
              {
                'name' => 'template-name',
                'type' => 'string'
              },
              {
                'name' => 'document-type',
                'type' => 'string'
              },
              {
                'name' => 'generate-pdf',
                'type' => 'boolean'
              },
              {
                'name' => 'force-regeneration',
                'type' => 'boolean'
              },
              {
                'name' => 'created-at',
                'type' => 'timestamp'
              },
              {
                'name' => 'updated-at',
                'type' => 'timestamp'
              }
            ]
          }
        ]
      end,

      sample_output: lambda do |connection, input|
        {
          'id' => '12345',
          'type' => 'project-documents',
          'attributes' => {
            'status' => 'finished',
            'error-text' => nil,
            'document-url' => 'https://example.com/documents/12345.pdf',
            'template-id' => '67890',
            'template-name' => 'Sample Template',
            'document-type' => 'sow',
            'generate-pdf' => true,
            'force-regeneration' => true,
            'created-at' => '2024-03-17T22:34:56Z',
            'updated-at' => '2024-03-17T22:35:01Z'
          }
        }
      end
    },

    create_or_update_service_location: {
      title: "Create or Update Service Location",
      subtitle: "Create a new service location or update an existing one",
      description: "Create or update a service location for a project in ScopeStack",
      help: {
        body: "This action creates a new service location or updates an existing one. There are several ways to update an existing location:\n\n" +
              "1. Provide a Service Location ID to directly update that specific location\n" +
              "2. If no ID is provided but a location with the same name already exists for the project, that location will be updated instead\n\n" +
              "Note: Service location names must be unique within a project. If you try to create a location with a name that already exists, " +
              "the action will automatically update the existing location instead of creating a new one.",
        learn_more_url: "https://support.scopestack.io/help",
        learn_more_text: "Learn more about service locations"
      },

      input_fields: lambda do |object_definitions, connection|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        # Fetch service location variables
        variables_response = get("/#{account_slug}/v1/project-variables")
                             .params(filter: { 'variable-context': 'service_location' })
                             .headers('Accept': 'application/vnd.api+json')
                             .after_error_response(/.*/) do |_code, body, _header, message|
                               error("Failed to fetch service location variables: #{message}: #{body}")
                             end

        # Start with standard fields
        fields = [
          {
            name: "id",
            label: "Service Location ID",
            type: "string", 
            control_type: "text",
            optional: true,
            sticky: true,
            hint: "Leave blank to create a new service location or update by name"
          },
          {
            name: "project_id",
            label: "Project ID",
            type: "string",
            control_type: "text",
            optional: false,
            sticky: true,
            hint: "ID of the project this service location belongs to"
          },
          {
            name: "name",
            label: "Location Name",
            type: "string",
            control_type: "text",
            optional: false,
            sticky: true,
            hint: "Name of the service location"
          },
          {
            name: "street",
            label: "Street",
            type: "string",
            control_type: "text",
            optional: false,
            hint: "Street address"
          },
          {
            name: "street2",
            label: "Street 2",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "Additional street address information"
          },
          {
            name: "city",
            label: "City",
            type: "string",
            control_type: "text",
            optional: false,
            hint: "City"
          },
          {
            name: "state",
            label: "State",
            type: "string",
            control_type: "text",
            optional: false,
            hint: "State"
          },
          {
            name: "postal_code",
            label: "Postal Code",
            type: "string",
            control_type: "text",
            optional: false,
            hint: "Postal code"
          },
          {
            name: "country",
            label: "Country",
            type: "string",
            control_type: "text",
            optional: true,
            hint: "Country"
          },
          {
            name: "remote",
            label: "Remote",
            type: "boolean", 
            control_type: "checkbox",
            optional: true,
            default: false,
            hint: "Whether this is a remote service location"
          }
        ]

        # Add dynamic fields from variables
        if variables_response["data"].is_a?(Array)
          variables_response["data"].each do |var|
            field = {
              name: "var_#{var['attributes']['name']}",
              label: var['attributes']['label'],
              optional: !var['attributes']['required'],
              hint: "Service location variable: #{var['attributes']['label']}"
            }

            case var['attributes']['variable-type']
            when 'number'
              field[:type] = 'number'
              field[:control_type] = 'number'
              if var['attributes']['minimum'].present? || var['attributes']['maximum'].present?
                range_text = []
                range_text << "min: #{var['attributes']['minimum']}" if var['attributes']['minimum'].present?
                range_text << "max: #{var['attributes']['maximum']}" if var['attributes']['maximum'].present?
                field[:hint] = "#{field[:hint]} (#{range_text.join(', ')})"
              end
            when 'date'
              field[:type] = 'date'
              field[:control_type] = 'date'
            when 'text'
              field[:type] = 'string'
              if var['attributes']['select-options'].present?
                field[:control_type] = 'select'
                field[:pick_list] = var['attributes']['select-options'].map { |opt| [opt['key'], opt['value']] }
                field[:toggle_hint] = 'Select from list'
                field[:toggle_field] = {
                  name: field[:name],
                  label: field[:label],
                  type: 'string',
                  control_type: 'text',
                  optional: field[:optional],
                  toggle_hint: 'Use custom value'
                }
                
                # Find and set default option if one exists
                default_option = var['attributes']['select-options'].find do |opt|
                  opt['default'] == true || opt['default'] == 'true' || opt['default'].present?
                end
                field[:default] = default_option['key'] if default_option
              else
                field[:control_type] = 'text'
              end
            end

            fields << field
          end
        end

        fields
      end,
      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Validate project exists
        begin
          get("/#{account_slug}/v1/projects/#{input['project_id']}")
            .headers('Accept': 'application/vnd.api+json')
            .after_error_response(/.*/) do |_code, body, _header, message|
              error("Project not found: #{message}: #{body}")
            end
        rescue
          error("Failed to validate project existence")
        end

        # Extract service location variables from input
        service_location_variables = input.keys
                                        .select { |k| k.start_with?('var_') }
                                        .map do |k|
                                          var_name = k.sub('var_', '')
                                          { name: var_name, value: input[k] }
                                        end
                                        .reject { |v| v[:value].nil? }

        # Build the payload
              payload = {
                data: {
            type: "project-locations",
                  attributes: {
              "name": input['name'],
              "street": input['street'],
              "street2": input['street2'],
              "city": input['city'],
              "state": input['state'],
              "postal-code": input['postal_code'],
              "country": input['country'],
              "remote": input['remote'] || false,
              "project-variables": service_location_variables
                  },
                  relationships: {
              project: {
                      data: {
                  type: "projects",
                  id: input['project_id']
                      }
                    }
                  }
                }
              }

        # If ID is provided, update existing service location
        if input['id'].present?
          payload[:data][:id] = input['id']
          response = patch("/#{account_slug}/v1/project-locations/#{input['id']}")
                      .headers('Content-Type': 'application/vnd.api+json',
                              'Accept': 'application/vnd.api+json')
                      .payload(payload)
                      .after_error_response(/.*/) do |_code, body, _header, message|
                        error("Failed to update service location: #{message}: #{body}")
              end
            else
          # Get all service locations for this project
          existing_locations = get("/#{account_slug}/v1/project-locations")
                               .params('filter[project]': input['project_id'])
                               .headers('Accept': 'application/vnd.api+json')
                               .after_error_response(/.*/) do |_code, body, _header, message|
                                 error("Failed to check existing service locations: #{message}: #{body}")
                               end

          # Check if a location with this name exists (case insensitive)
          existing_location = existing_locations['data'].find { |loc| 
            loc['attributes']['name'].downcase == input['name'].downcase
          }

          if existing_location
            # Update the existing service location
            payload[:data][:id] = existing_location['id']
            
            response = patch("/#{account_slug}/v1/project-locations/#{existing_location['id']}")
                          .headers('Content-Type': 'application/vnd.api+json',
                                  'Accept': 'application/vnd.api+json')
                          .payload(payload)
                          .after_error_response(/.*/) do |_code, body, _header, message|
                          error("Failed to update existing service location: #{message}: #{body}")
                        end
          else
            # Create new service location
            response = post("/#{account_slug}/v1/project-locations")
                        .headers('Content-Type': 'application/vnd.api+json',
                                'Accept': 'application/vnd.api+json')
                        .payload(payload)
                        .after_error_response(/.*/) do |_code, body, _header, message|
                          if message.include?('has already been taken')
                            error("A service location with this name already exists for this project. Please use a different name or provide the existing location's ID to update it.")
                          else
                            error("Failed to create service location: #{message}: #{body}")
                          end
            end
          end
        end

        response["data"]
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['project_location']
      end
    },



    list_project_service_locations: {
      description: "List all service locations for a project",
      help: "This action retrieves all service locations associated with a specific project.",
      input_fields: lambda do |_object_definitions|
        [
          {
            name: 'project_id',
            label: 'Project ID',
            type: 'string',
            optional: false,
            hint: 'The ID of the project to list service locations for'
          }
        ]
      end,
      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Validate project_id is provided
        if input['project_id'].blank?
          error("Project ID is required to list service locations")
        end

        # Get all service locations for the project using filter
        response = get("/#{account_slug}/v1/project-locations")
                  .params('filter[project]': input['project_id'])
                  .headers('Accept': 'application/vnd.api+json')
                  .after_error_response(/.*/) do |_code, body, _header, message|
                    error("Failed to fetch service locations: #{message}: #{body}")
                  end

        # Return a hash with the data array
        {
          data: response['data']
        }
      end,
      output_fields: lambda do |object_definitions|
        [
          {
            name: 'data',
            label: 'Service Locations',
            type: 'array',
            of: 'object',
            properties: object_definitions['project_service_location']
          }
        ]
      end,
      sample_output: lambda do |_connection, _input|
        {
          data: [
            {
              id: '123',
              type: 'project-locations',
              attributes: {
                name: 'Sample Location',
                street: '123 Main St',
                city: 'Sample City',
                state: 'ST',
                'postal-code': '12345'
              }
            }
          ]
        }
      end
    },

    list_project_contacts: {
      description: "List all contacts for a project",
      help: "This action retrieves all contacts associated with a specific project.",
      input_fields: lambda do |_object_definitions|
        [
          {
            name: 'project_id',
            label: 'Project ID',
                  type: 'string',
            optional: false,
            hint: 'The ID of the project to list contacts for'
          }
        ]
      end,
      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Validate project_id is provided
        if input['project_id'].blank?
          error("Project ID is required to list contacts")
        end

        # Get all contacts for the project
        response = get("/#{account_slug}/v1/projects/#{input['project_id']}/project-contacts")
                  .params('page[size]': 200)
                  .headers('Accept': 'application/vnd.api+json')
                  .after_error_response(/.*/) do |_code, body, _header, message|
                    error("Failed to fetch project contacts: #{message}: #{body}")
                  end

        # Return a hash with the data array
        {
          data: response['data']
        }
      end,
      output_fields: lambda do |object_definitions|
        [
          {
            name: 'data',
            label: 'Project Contacts',
            type: 'array',
            of: 'object',
            properties: object_definitions['project_contact']
          }
        ]
      end,
      sample_output: lambda do |_connection, _input|
        {
          data: [
            {
              id: '203822',
              type: 'project-contacts',
              attributes: {
                active: true,
                name: 'Contact Name',
                title: 'Contact Title',
                email: 'email@email.com',
                phone: '555-555-5555',
                contact_type: 'primary_customer_contact',
                project_variables: []
              }
            }
          ]
        }
      end
    },
 
    create_or_update_project_contact: {
      description: "Create or update a project contact",
      help: "This action creates a new project contact or updates an existing one if an ID is provided. If a contact with the same name exists on the project, it will be updated instead of creating a new one.",
      input_fields: lambda do |_object_definitions, connection|
        puts "DEBUG: Starting create_or_update_project_contact input_fields"
        puts "DEBUG: Connection in input_fields: #{connection.inspect}"
        
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        puts "DEBUG: Account info in input_fields: #{account_info.inspect}"
        account_slug = account_info[:account_slug]
    
        # Fetch all project variables for contact context
        project_variables_response = get("/#{account_slug}/v1/project-variables")
                                     .params(filter: { 'variable-context': 'project_contact' })
                              .headers('Accept': 'application/vnd.api+json')
                              .after_error_response(/.*/) do |_code, body, _header, message|
                                error("Failed to fetch project variables: #{message}: #{body}")
                              end
    
        # Create fields array
        fields = [
          {
            name: 'id',
            label: 'Contact ID',
            type: 'string',
            optional: true,
            hint: 'The ID of the contact to update. If not provided, a new contact will be created or an existing one with the same name will be updated.'
          },
          {
            name: 'project_id',
            label: 'Project ID',
            type: 'string',
            optional: false,
            hint: 'The ID of the project to create/update the contact for'
          },
          {
            name: 'name',
            label: 'Name',
            type: 'string',
            optional: false,
            hint: 'If a contact with this name already exists on the project, it will be updated instead of creating a new one.'
          },
          {
            name: 'title',
            label: 'Title',
            type: 'string',
                optional: true 
              },
              { 
            name: 'email',
            label: 'Email',
            type: 'string',
            optional: true
          },
          {
            name: 'phone',
            label: 'Phone',
            type: 'string',
            optional: true
          },
          {
            name: 'contact_type',
            label: 'Contact Type',
            type: 'string',
            optional: false,
            control_type: 'select',
            pick_list: [
              ['Primary Customer Contact', 'primary_customer_contact'],
              ['Customer Contact', 'customer_contact']
            ]
          }
        ]

        # Add project variables as dynamic fields
        project_variables_response['data'].each do |var|
          field_name = "var_#{var['attributes']['name']}"
            field = {
            name: field_name,
              label: var['attributes']['label'],
            type: 'string',
              optional: !var['attributes']['required'],
            hint: var['attributes']['description']
            }
    
          # Add control type based on variable type
            case var['attributes']['variable-type']
            when 'number'
              field[:control_type] = 'number'
            when 'date'
              field[:control_type] = 'date'
            when 'text'
              if var['attributes']['select-options'].present?
                field[:control_type] = 'select'
                field[:pick_list] = var['attributes']['select-options'].map do |opt|
                  [opt['value'], opt['key']]
                end
                
                # Find and set default option if one exists
                default_option = var['attributes']['select-options'].find do |opt| 
                  opt['default'] == true || opt['default'] == 'true' || opt['default'].present?
                end
                field[:default] = default_option['key'] if default_option
              end
            end
    
            fields << field
          end
    
        fields
      end,
      execute: lambda do |connection, input|
        # Get account information using the reusable method
        puts "DEBUG: Starting create_or_update_project_contact execute"
        puts "DEBUG: Connection in execute: #{connection.inspect}"
        puts "DEBUG: Input in execute: #{input.inspect}"
        
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        puts "DEBUG: Account info in execute: #{account_info.inspect}"
        account_slug = account_info[:account_slug]

        # Validate required fields
        if input['project_id'].blank?
          error("Project ID is required")
        end

        if input['name'].blank?
          error("Name is required")
        end

        if input['contact_type'].blank?
          error("Contact Type is required")
        end

        # Fetch project variables to get their types (reuse the response from input_fields)
        project_variables_response = get("/#{account_slug}/v1/project-variables")
                                     .params(filter: { 'variable-context': 'project_contact' })
                                     .headers('Accept': 'application/vnd.api+json')
                                     .after_error_response(/.*/) do |_code, body, _header, message|
                                       error("Failed to fetch project variables: #{message}: #{body}")
                                     end

        # Create lookup for variable types
        variable_types = project_variables_response['data'].each_with_object({}) do |var, hash|
          hash[var['attributes']['name']] = var['attributes']
        end

        # Helper function to process variable value based on its type
        process_variable_value = lambda do |name, value|
          return nil if value.nil?
          var_attrs = variable_types[name]
          return value unless var_attrs  # Return as is if we don't have type info
          
          case var_attrs['variable-type']
          when 'number'
            if var_attrs['select-options'].present?
              # For number select fields, find the matching option value
              option = var_attrs['select-options'].find { |opt| opt['key'].to_s == value.to_s }
              option ? option['value'].to_i : value.to_i
            else
              value.to_i
            end
          when 'date'
            value.to_s  # Ensure date is sent as string
          when 'text'
            if var_attrs['select-options'].present?
              # For text select fields, find the matching option value
              option = var_attrs['select-options'].find { |opt| opt['key'].to_s == value.to_s }
              option ? option['value'].to_s : value.to_s
            else
              value.to_s
            end
          else
            value.to_s
          end
        end

        # Extract and process project variables from input
        project_variables = input.keys
                               .select { |k| k.start_with?('var_') }
                               .map do |k|
                                 var_name = k.sub('var_', '')
                                 var_value = process_variable_value.call(var_name, input[k])
                                 { name: var_name, value: var_value }
                               end.reject { |v| v[:value].nil? }

        # Prepare the payload
              payload = {
          data: {
            type: 'project-contacts',
            attributes: {
              name: input['name'],
              title: input['title'],
              email: input['email'],
              phone: input['phone'],
              'contact-type': input['contact_type'],
              'project-variables': project_variables
            },
            relationships: {
              project: {
                data: {
                  type: 'projects',
                  id: input['project_id']
                }
              }
            }
          }
        }
    
        # Make the request
        response = if input['id'].present?
          # Update existing contact
          payload[:data][:id] = input['id']
          patch("/#{account_slug}/v1/project-contacts/#{input['id']}")
            .payload(payload)
            .headers('Accept': 'application/vnd.api+json',
                    'Content-Type': 'application/vnd.api+json')
            .after_error_response(/.*/) do |_code, body, _header, message|
              error("Failed to update project contact: #{message}: #{body}")
            end
        else
          # Check for existing contact with same name
          existing_contacts = get("/#{account_slug}/v1/project-contacts")
                              .params('filter[project]': input['project_id'])
                                      .headers('Accept': 'application/vnd.api+json')
                                      .after_error_response(/.*/) do |_code, body, _header, message|
                                error("Failed to check existing contacts: #{message}: #{body}")
                              end

          # Find contact with matching name (case insensitive)
          existing_contact = existing_contacts['data'].find { |contact| 
            contact['attributes']['name'].downcase == input['name'].downcase
          }

          if existing_contact
            # Update existing contact
            payload[:data][:id] = existing_contact['id']
            patch("/#{account_slug}/v1/project-contacts/#{existing_contact['id']}")
              .payload(payload)
              .headers('Accept': 'application/vnd.api+json',
                      'Content-Type': 'application/vnd.api+json')
              .after_error_response(/.*/) do |_code, body, _header, message|
                error("Failed to update existing contact: #{message}: #{body}")
              end
          else
            # Create new contact
            post("/#{account_slug}/v1/project-contacts")
                .payload(payload)
                .headers('Accept': 'application/vnd.api+json',
                        'Content-Type': 'application/vnd.api+json')
                .after_error_response(/.*/) do |_code, body, _header, message|
                error("Failed to create project contact: #{message}: #{body}")
            end
            end
          end
          
        response
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['project_contact']
      end,
      sample_output: lambda do |_connection, _input|
        {
          data: {
            id: '203822',
            type: 'project-contacts',
            attributes: {
              active: true,
              name: 'Contact Name',
              title: 'Contact Title',
              email: 'email@email.com',
              phone: '555-555-5555',
              contact_type: 'primary_customer_contact',
              project_variables: []
            }
          }
        }
      end
    },
 
    get_project: {
      title: "Get Project",
      subtitle: "Get project details from ScopeStack",
      description: "Get <span class='provider'>project</span> details from <span class='provider'>ScopeStack</span>",
      help: "Retrieves project details using Project ID. Optionally includes related data like client, sales executive, etc.",
     
      input_fields: lambda do |object_definitions|
        [
          {
            name: 'project_id',
            label: 'Project ID',
            type: 'string',
            optional: false,
            hint: 'Enter the ID of the project to retrieve'
          },
          {
            name: "includes",
            label: "Include Related Data",
            type: "object",
            properties: [
              # Core Project Data
              {
                name: 'include_account',
                label: 'Account',
                control_type: 'checkbox',
                type: 'boolean',
            optional: true,
                sticky: true,
                hint: 'Include account information'
              },
              {
                name: 'include_business_unit',
                label: 'Business Unit',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include business unit information'
              },
              {
                name: 'include_client',
                label: 'Client',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include client information'
              },
              {
                name: 'include_creator',
                label: 'Creator',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include creator information'
              },
              {
                name: 'include_sales_executive',
                label: 'Sales Executive',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include sales executive information'
              },
              {
                name: 'include_presales_engineer',
                label: 'Presales Engineer',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include presales engineer information'
              },
              # Project Management
              {
                name: 'include_psa_project',
                label: 'PSA Project',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include PSA project information'
              },
              {
                name: 'include_project_phases',
                label: 'Project Phases',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project phases information'
              },
              {
                name: 'include_project_versions',
                label: 'Project Versions',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project versions information'
              },
              # Resources and Planning
              {
                name: 'include_project_resources',
                label: 'Project Resources',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project resources information'
              },
              {
                name: 'include_resource_plans',
                label: 'Resource Plans',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include resource plans information'
              },
              {
                name: 'include_resource_rates',
                label: 'Resource Rates',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include resource rates information'
              },
              # Financial Information
              {
                name: 'include_payment_term',
                label: 'Payment Term',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include payment term information'
              },
              {
                name: 'include_rate_table',
                label: 'Rate Table',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include rate table information'
              },
              {
                name: 'include_project_credits',
                label: 'Project Credits',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project credits information'
              },
              {
                name: 'include_project_expenses',
                label: 'Project Expenses',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project expenses information'
              },
              {
                name: 'include_pricing_adjustments',
                label: 'Pricing Adjustments',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include pricing adjustments information'
              },
              # Documents and Attachments
              {
                name: 'include_document_template',
                label: 'Document Template',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include document template information'
              },
              {
                name: 'include_project_documents',
                label: 'Project Documents',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project documents information'
              },
              {
                name: 'include_project_attachments',
                label: 'Project Attachments',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project attachments information'
              },
              # Project Details
              {
                name: 'include_project_collaborators',
                label: 'Project Collaborators',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project collaborators information'
              },
              {
                name: 'include_project_contacts',
                label: 'Project Contacts',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project contacts information'
              },
              {
                name: 'include_project_conditions',
                label: 'Project Conditions',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project conditions information'
              },
              {
                name: 'include_project_governances',
                label: 'Project Governances',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project governances information'
              },
              {
                name: 'include_project_locations',
                label: 'Project Locations',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project locations information'
              },
              {
                name: 'include_project_products',
                label: 'Project Products',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project products information'
              },
              {
                name: 'include_project_services',
                label: 'Project Services',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project services information'
              },
              # Additional Information
              {
                name: 'include_external_request',
                label: 'External Request',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include external request information'
              },
              {
                name: 'include_crm_opportunity',
                label: 'CRM Opportunity',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include CRM opportunity information'
              },
              {
                name: 'include_approval_steps',
                label: 'Approval Steps',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include approval steps information'
              },
              {
                name: 'include_customer_successes',
                label: 'Customer Successes',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include customer successes information'
              },
              {
                name: 'include_notes',
                label: 'Notes',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include notes information'
              },
              {
                name: 'include_quotes',
                label: 'Quotes',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include quotes information'
              },
              {
                name: 'include_audit_logs',
                label: 'Audit Logs',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include audit logs information'
              },
              {
                name: 'include_partner_requests',
                label: 'Partner Requests',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include partner requests information'
              }
            ]
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        project_id = input['project_id']
        includes = []
        
        # Build includes array from checkbox inputs
        input['includes']&.each do |key, value|
          if value == 'true'
            # Convert include_account to account, include_business_unit to business-unit, etc.
            include_key = key.to_s.gsub('include_', '').gsub('_', '-')
            includes << include_key
          end
        end

        # Build query parameters
        query_params = {}
        query_params['include'] = includes.join(',') if includes.any?

        # Get project details with includes
        response = get("/#{account_slug}/v1/projects/#{project_id}", query_params).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end

        # Flatten the response for easier condition testing
        if response['data']
          project_data = response['data']
          attributes = project_data['attributes'] || {}
          
          flattened_response = {
            # Flattened fields for easier condition testing
            'id' => project_data['id'],
            'type' => project_data['type'],
            'status' => attributes['status'],
            'project_name' => attributes['project-name'],
            'client_name' => attributes['client-name'],
            'presales_engineer_name' => attributes['presales-engineer-name'],
            'sales_executive_name' => attributes['sales-executive-name'],
            'created_at' => attributes['created-at'],
            'updated_at' => attributes['updated-at'],
            'submitted_at' => attributes['submitted-at'],
            'approved_at' => attributes['approved-at'],
            'active' => attributes['active'],
            # Full nested structure for complete data access
            'data' => response['data']
          }
          
          # Add meta if present
          flattened_response['meta'] = response['meta'] if response['meta']
          
          flattened_response
        else
          response
        end
      end,

      output_fields: lambda do |object_definitions|
        [
          # Flattened fields for easier condition testing
          { name: "id", type: "integer", label: "Project ID" },
          { name: "type", type: "string", label: "Type" },
          { name: "status", type: "string", label: "Status" },
          { name: "project_name", type: "string", label: "Project Name" },
          { name: "client_name", type: "string", label: "Client Name" },
          { name: "presales_engineer_name", type: "string", label: "Presales Engineer Name" },
          { name: "sales_executive_name", type: "string", label: "Sales Executive Name" },
          { name: "created_at", type: "timestamp", label: "Created At" },
          { name: "updated_at", type: "timestamp", label: "Updated At" },
          { name: "submitted_at", type: "timestamp", label: "Submitted At" },
          { name: "approved_at", type: "timestamp", label: "Approved At" },
          { name: "active", type: "boolean", label: "Active" },
          # Full nested structure for complete data access
          {
            name: "data",
            type: "object",
            properties: object_definitions['project']
          }
        ]
      end,

      sample_output: lambda do |connection, input|
        # Get a sample project with minimal filters
        sample_input = {
          'page_size' => 1,
          'page_number' => 1
        }
        call('list_projects', sample_input)
      end
    },
 
    list_projects: {
      title: "List Projects",
      subtitle: "List projects from ScopeStack",
      description: "List <span class='provider'>projects</span> from <span class='provider'>ScopeStack</span>",
      help: "Retrieves a list of projects with optional filters and pagination support.",

      input_fields: lambda do |object_definitions|
        [
          {
            name: "filters",
            label: "Filters",
            type: "object",
            properties: [
              {
                name: 'project_name',
                label: 'Project Name',
                control_type: 'text',
            type: 'string',
                optional: true,
                sticky: true,
                hint: 'Filter by project name'
          },
          {
                name: 'status',
                label: 'Status',
            type: 'string',
                control_type: 'text',
                optional: true,
                sticky: true,
                hint: 'Enter comma-separated list of statuses. Available values: building, technical_approval, sales_approval, business_approval, approved, won, lost, canceled'
              },
              {
                name: 'creator_id',
                label: 'Creator ID',
            type: 'string',
                optional: true,
                hint: 'Filter projects by creator ID'
          },
          {
                name: 'team_id',
                label: 'Team ID',
            type: 'string',
                optional: true,
                hint: 'Filter projects by team ID'
          },
          {
                name: 'collaborator_id',
                label: 'Collaborator ID',
            type: 'string',
                optional: true,
                hint: 'Filter projects by collaborator ID'
          },
          {
                name: 'client_id',
                label: 'Client ID',
            type: 'string',
                optional: true,
                hint: 'Filter projects by client ID'
          },
          {
                name: 'client_name',
                label: 'Client Name',
            type: 'string',
                optional: true,
                hint: 'Filter projects by client name'
              },
              {
                name: 'presales_engineer_id',
                label: 'Presales Engineer ID',
            type: 'string',
                optional: true,
                hint: 'Filter projects by presales engineer ID'
              },
              {
                name: 'presales_engineer_name',
                label: 'Presales Engineer Name',
                type: 'string',
                optional: true,
                hint: 'Filter projects by presales engineer name'
              },
              {
                name: 'sales_executive_id',
                label: 'Sales Executive ID',
                type: 'string',
                optional: true,
                hint: 'Filter projects by sales executive ID'
              },
              {
                name: 'sales_executive_name',
                label: 'Sales Executive Name',
                type: 'string',
                optional: true,
                hint: 'Filter projects by sales executive name'
              },
              {
                name: 'created_after',
                label: 'Created After',
                type: 'date_time',
                optional: true,
                hint: 'Filter projects created after this date/time'
              },
              {
                name: 'created_before',
                label: 'Created Before',
                type: 'date_time',
                optional: true,
                hint: 'Filter projects created before this date/time'
              },
              {
                name: 'updated_after',
                label: 'Updated After',
                type: 'date_time',
                optional: true,
                hint: 'Filter projects updated after this date/time'
              },
              {
                name: 'updated_before',
                label: 'Updated Before',
                type: 'date_time',
                optional: true,
                hint: 'Filter projects updated before this date/time'
              },
              {
                name: 'project_tags',
                label: 'Project Tags',
                type: 'string',
                optional: true,
                control_type: 'text',
                sticky: true,
                hint: lambda do |connection, input|
                  # Get available tags for help text
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
                  begin
                    response = get("/#{account_slug}/v1/tags")
                    if response['data'].is_a?(Array)
                      available_tags = response['data'].map { |tag| tag.dig('attributes', 'name') }.compact.join(', ')
                      "Enter comma-separated list of tags. Available tags: #{available_tags}"
                    else
                      "Enter comma-separated list of tags"
                    end
                  rescue
                    "Enter comma-separated list of tags"
                  end
                end
              },
              {
                name: 'active',
                label: 'Return Active or Archived?',
                type: 'string',
                control_type: 'select',
            optional: true,
                sticky: true,
                pick_list: [
                  ['Active Only', 'true'],
                  ['Archived Only', 'false'],
                  ['Both Active and Archived', 'both']
                ],
                hint: 'Select which projects to return: "Active Only" returns only active projects, "Archived Only" returns only archived projects, and "Both Active and Archived" returns all projects regardless of status.'
              },
              {
                name: 'service_id',
                label: 'Service ID',
            type: 'string',
                optional: true,
                hint: 'Filter projects by service ID'
              }
            ]
          },
          {
            name: "includes",
            label: "Include Related Data",
            type: "object",
            properties: [
              # Core Project Data
              {
                name: 'include_account',
                label: 'Account',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include account information'
              },
              {
                name: 'include_business_unit',
                label: 'Business Unit',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include business unit information'
              },
              {
                name: 'include_client',
                label: 'Client',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include client information'
              },
              {
                name: 'include_creator',
                label: 'Creator',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include creator information'
              },
              {
                name: 'include_sales_executive',
                label: 'Sales Executive',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include sales executive information'
              },
              {
                name: 'include_presales_engineer',
                label: 'Presales Engineer',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include presales engineer information'
              },
              # Project Management
              {
                name: 'include_psa_project',
                label: 'PSA Project',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include PSA project information'
              },
              {
                name: 'include_project_phases',
                label: 'Project Phases',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project phases information'
              },
              {
                name: 'include_project_versions',
                label: 'Project Versions',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project versions information'
              },
              # Resources and Planning
              {
                name: 'include_project_resources',
                label: 'Project Resources',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project resources information'
              },
              {
                name: 'include_resource_plans',
                label: 'Resource Plans',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include resource plans information'
              },
              {
                name: 'include_resource_rates',
                label: 'Resource Rates',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include resource rates information'
              },
              # Financial Information
              {
                name: 'include_payment_term',
                label: 'Payment Term',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include payment term information'
              }
            ]
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        filters = {}
        
        # Add filters if provided
        filters["filter[project-name]"] = input['filters']['project_name'] if input.dig('filters', 'project_name').present?
        filters["filter[status]"] = input['filters']['status']&.split(',')&.map(&:strip)&.join(',') if input.dig('filters', 'status').present?
        filters["filter[creator_id]"] = input['filters']['creator_id'] if input.dig('filters', 'creator_id').present?
        filters["filter[team_id]"] = input['filters']['team_id'] if input.dig('filters', 'team_id').present?
        filters["filter[collaborator_id]"] = input['filters']['collaborator_id'] if input.dig('filters', 'collaborator_id').present?
        filters["filter[client_id]"] = input['filters']['client_id'] if input.dig('filters', 'client_id').present?
        filters["filter[client_name]"] = input['filters']['client_name'] if input.dig('filters', 'client_name').present?
        filters["filter[presales_engineer_id]"] = input['filters']['presales_engineer_id'] if input.dig('filters', 'presales_engineer_id').present?
        filters["filter[presales_engineer_name]"] = input['filters']['presales_engineer_name'] if input.dig('filters', 'presales_engineer_name').present?
        filters["filter[sales_executive_id]"] = input['filters']['sales_executive_id'] if input.dig('filters', 'sales_executive_id').present?
        filters["filter[sales_executive_name]"] = input['filters']['sales_executive_name'] if input.dig('filters', 'sales_executive_name').present?
        filters["filter[created_after]"] = input['filters']['created_after'] if input.dig('filters', 'created_after').present?
        filters["filter[created_before]"] = input['filters']['created_before'] if input.dig('filters', 'created_before').present?
        filters["filter[updated_after]"] = input['filters']['updated_after'] if input.dig('filters', 'updated_after').present?
        filters["filter[updated_before]"] = input['filters']['updated_before'] if input.dig('filters', 'updated_before').present?
        filters["filter[tags]"] = input['filters']['project_tags']&.split(',')&.map(&:strip)&.join(',') if input.dig('filters', 'project_tags').present?
        if input.dig('filters', 'active') == 'both'
          # Make two separate calls and combine results
          active_projects = get("/#{account_slug}/v1/projects")
            .params(filters.merge("filter[active]" => "true"))
            .after_error_response(/.*/) do |_code, body, _header, message|
              error("#{message}: #{body}")
            end

          inactive_projects = get("/#{account_slug}/v1/projects")
            .params(filters.merge("filter[active]" => "false"))
            .after_error_response(/.*/) do |_code, body, _header, message|
              error("#{message}: #{body}")
            end

          # Combine the results and return immediately
          all_data = (active_projects['data'] || []) + (inactive_projects['data'] || [])
          return {
            data: all_data,
            meta: {
              total_count: all_data.size
            }
          }
        else
          filters["filter[active]"] = input['filters']['active'] if input.dig('filters', 'active').present?
        end

        # Rest of the code (pagination) only runs if we're not in the 'both' case
        filters["filter[service_id]"] = input['filters']['service_id'] if input.dig('filters', 'service_id').present?
        filters["filter[rate_table_id]"] = input['filters']['rate_table_id'] if input.dig('filters', 'rate_table_id').present?
        
        # Build includes array from checkboxes
        includes = []
        includes << 'account' if input.dig('includes', 'include_account')
        includes << 'business-unit' if input.dig('includes', 'include_business_unit')
        includes << 'client' if input.dig('includes', 'include_client')
        includes << 'creator' if input.dig('includes', 'include_creator')
        includes << 'document-template' if input.dig('includes', 'include_document_template')
        includes << 'external-request' if input.dig('includes', 'include_external_request')
        includes << 'sales-executive' if input.dig('includes', 'include_sales_executive')
        includes << 'presales-engineer' if input.dig('includes', 'include_presales_engineer')
        includes << 'psa-project' if input.dig('includes', 'include_psa_project')
        includes << 'payment-term' if input.dig('includes', 'include_payment_term')
        includes << 'rate-table' if input.dig('includes', 'include_rate_table')
        includes << 'crm-opportunity' if input.dig('includes', 'include_crm_opportunity')
        includes << 'approval-steps' if input.dig('includes', 'include_approval_steps')
        includes << 'customer-successes' if input.dig('includes', 'include_customer_successes')
        includes << 'notes' if input.dig('includes', 'include_notes')
        includes << 'project-attachments' if input.dig('includes', 'include_project_attachments')
        includes << 'project-collaborators' if input.dig('includes', 'include_project_collaborators')
        includes << 'project-contacts' if input.dig('includes', 'include_project_contacts')
        includes << 'project-conditions' if input.dig('includes', 'include_project_conditions')
        includes << 'project-credits' if input.dig('includes', 'include_project_credits')
        includes << 'project-documents' if input.dig('includes', 'include_project_documents')
        includes << 'project-expenses' if input.dig('includes', 'include_project_expenses')
        includes << 'project-governances' if input.dig('includes', 'include_project_governances')
        includes << 'project-locations' if input.dig('includes', 'include_project_locations')
        includes << 'project-products' if input.dig('includes', 'include_project_products')
        includes << 'project-phases' if input.dig('includes', 'include_project_phases')
        includes << 'project-resources' if input.dig('includes', 'include_project_resources')
        includes << 'resource-plans' if input.dig('includes', 'include_resource_plans')
        includes << 'project-services' if input.dig('includes', 'include_project_services')
        includes << 'partner-requests' if input.dig('includes', 'include_partner_requests')
        includes << 'project-versions' if input.dig('includes', 'include_project_versions')
        includes << 'resource-rates' if input.dig('includes', 'include_resource_rates')
        includes << 'quotes' if input.dig('includes', 'include_quotes')
        includes << 'audit-logs' if input.dig('includes', 'include_audit_logs')
        includes << 'pricing-adjustments' if input.dig('includes', 'include_pricing_adjustments')
        
        # Add includes to filters if any are selected
        filters["include"] = includes.join(',') if includes.any?
        
        # Set a reasonable page size for each request
        filters["page[size]"] = 100

        all_data = []
        current_page = 1
        has_more_pages = true

        while has_more_pages
          filters["page[number]"] = current_page
          
          response = get("/#{account_slug}/v1/projects")
            .params(filters)
                        .after_error_response(/.*/) do |_code, body, _header, message|
              error("#{message}: #{body}")
            end
          
          # Add the current page's data to our collection
          all_data.concat(response['data'] || [])
          
          # Process included data to add integer conversions for governances
          if response['included']
            response['included'].each do |included_item|
              if included_item['type'] == 'project-governances' || included_item['type'] == 'governances'
                attrs = included_item['attributes'] || {}
                if attrs['rate'].present?
                  attrs['rate_in_cents'] = (attrs['rate'].to_f * 100).to_i
                end
                if attrs['fixed-hours'].present?
                  attrs['fixed_hours_in_minutes'] = (attrs['fixed-hours'].to_f * 60).to_i
                end
                if attrs['hours'].present? && included_item['type'] == 'project-governances'
                  attrs['hours_in_minutes'] = (attrs['hours'].to_f * 60).to_i
                end
              end
            end
          end

          # Check if there are more pages
          total_pages = response.dig('meta', 'total_pages') || 1
          has_more_pages = current_page < total_pages
          current_page += 1
        end
        
        # Process main data for any governances that might be in relationships
        all_data.each do |project|
          # Process included project-governances if they're in the project data
          if project['attributes'] && project['attributes']['project-governances']
            # This would be handled by the included processing above
          end
        end

        # Return the combined data
        {
          data: all_data,
          meta: {
            total_count: all_data.size
          }
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: 'data',
            label: 'Projects',
            type: 'array',
            of: 'object',
            properties: object_definitions['project']
          },
          {
            name: 'meta',
            label: 'Metadata',
            type: 'object',
                    properties: [
              {
                name: 'total_count',
                label: 'Total Count',
                type: 'integer'
              }
            ]
          }
        ]
      end,

      sample_output: lambda do |connection, input|
        # Make a test API call with minimal filters
        response = get("/api/v1/projects")
          .params(
            "page[size]" => 1,
            "include" => "client,creator"
          )
          .after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end

        {
          data: response['data'] || [],
          meta: {
            total_count: response.dig('meta', 'total_count') || 1
          }
        }
      end
    },

    find_sales_executive: {
      title: "Get Sales Executive",
      subtitle: "Find a sales executive by ID, name, or email",
      description: "Find a <span class='provider'>sales executive</span> in <span class='provider'>ScopeStack</span>",
      help: "Search for a sales executive by ID, name, or email. If searching by name or email, will error if multiple matches are found.",

      input_fields: lambda do |object_definitions|
        [
              {
                name: "id",
                label: "Sales Executive ID",
                type: "string",
                optional: true,
            hint: "If provided, will search by ID. Otherwise, must provide either name or email."
              },
              {
                name: "name",
            label: "Name",
                type: "string",
                optional: true,
            hint: "Search by name. Will error if multiple matches found."
              },
              {
                name: "email",
            label: "Email",
                type: "string",
                optional: true,
            hint: "Search by email. Will error if multiple matches found."
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Validate that at least one search parameter is provided
        if !input['id'].present? && !input['name'].present? && !input['email'].present?
          error("You must provide at least one of: Sales Executive ID, Name, or Email to search.")
        end

        # Validate that we're not mixing ID search with name/email search
        if input['id'].present? && (input['name'].present? || input['email'].present?)
          error("Cannot search by ID while also searching by name or email. Please use only one search method.")
        end

        # Validate email format if provided
        if input['email'].present?
          email = input['email'].strip
          unless email =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
            error("Invalid email format: #{email}")
          end
        end

        # If ID is provided, search by ID
        if input['id'].present?
          response = get("/#{account_slug}/v1/sales-executives/#{input['id']}")
                      .headers('Accept': 'application/vnd.api+json')
                      .after_error_response(/.*/) do |_code, body, _header, message|
                        if _code == 404
                          error("Sales Executive with ID #{input['id']} not found")
                        else
                          error("Failed to fetch sales executive: #{message}: #{body}")
            end
          end
          
          if response['data'].nil?
            error("Sales Executive with ID #{input['id']} not found")
          end

          return response['data']
        end

        # Build filter parameters for name/email search
        filter_params = {}
        filter_params[:name] = input['name'] if input['name'].present?
        filter_params[:email] = input['email'] if input['email'].present?

        # Search by name/email
        response = get("/#{account_slug}/v1/sales-executives")
                  .headers('Accept': 'application/vnd.api+json')
                  .params(filter: filter_params)
                  .after_error_response(/.*/) do |_code, body, _header, message|
                    error("Failed to search for sales executive: #{message}: #{body}")
                  end

        # Check results
        if response['data'].nil? || response['data'].empty?
          search_criteria = []
          search_criteria << "name: #{input['name']}" if input['name'].present?
          search_criteria << "email: #{input['email']}" if input['email'].present?
          error("No sales executive found matching #{search_criteria.join(' and ')}")
        end

        if response['data'].length > 1
          search_criteria = []
          search_criteria << "name: #{input['name']}" if input['name'].present?
          search_criteria << "email: #{input['email']}" if input['email'].present?
          error("Multiple sales executives found matching #{search_criteria.join(' and ')}. Please use ID for exact match.")
        end

        response['data'].first
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['sales_executive']
      end,

      sample_output: lambda do |connection, input|
        {
          "id" => "123",
          "type" => "sales-executives",
          "attributes" => {
            "name" => "John Doe",
            "email" => "john.doe@example.com",
            "title" => "Sales Executive",
            "phone" => "+1 (555) 123-4567",
            "active" => true
          }
        }
      end
    },

    list_crm_opportunities: {
      title: "List CRM Opportunities",
      subtitle: "Get a list of CRM opportunities with optional filters",
      description: "List <span class='provider'>CRM opportunities</span> from <span class='provider'>ScopeStack</span>",
      help: "Retrieves a list of CRM opportunities. You can filter by closed status, display name, or opportunity ID. The display name filter will match any opportunity where the display name contains the provided text.",
    
      input_fields: lambda do |object_definitions|
        [
          {
            name: "is_closed",
            type: "boolean",
            control_type: "checkbox",
            label: "Is Closed",
            hint: "Filter for closed opportunities when checked, active opportunities when unchecked",
                optional: true
              },
              { 
            name: "display_name",
                type: "string",
                control_type: "text",
            label: "Display Name Contains",
            hint: "Filter opportunities where the display name contains this text",
                optional: true
              },
              {
            name: "opportunity_id",
                type: "string",
                control_type: "text",
            label: "Opportunity ID",
            hint: "Filter by exact opportunity ID from the foreign CRM",
                optional: true
          }
        ]
      end,
    
      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
    
        # Build filter parameters
        filter_params = {}
        filter_params["is-closed"]      = input["is_closed"]      if input["is_closed"].present?
        filter_params["display-name"]   = input["display_name"]   if input["display_name"].present?
        filter_params["opportunity-id"] = input["opportunity_id"] if input["opportunity_id"].present?
    
        # Make the API call (OAuth 'apply' block adds Authorization header)
        response = get("/#{account_slug}/v1/crm-opportunities")
                   .params(filter: filter_params)
                   .headers("Accept": "application/vnd.api+json")
                      .after_error_response(/.*/) do |_code, body, _header, message|
                     error("Failed to fetch CRM opportunities: #{message}: #{body}")
                   end
    
        response
      end,
    
      output_fields: lambda do |object_definitions|
        [
          {
            name: "data",
            type: "array",
            of: "object",
            properties: [
              { name: "id",   type: "integer",  label: "ID" },
              { name: "type", type: "string",  label: "Type" },
              {
                name: "attributes",
                type: "object",
                properties: [
                  { name: "opportunity-id", type: "string",  label: "Opportunity ID" },
                  { name: "name",           type: "string",  label: "Name" },
                  { name: "display-name",   type: "string",  label: "Display Name" },
                  { name: "amount",         type: "string",  label: "Amount" },
                  { name: "stage",          type: "string",  label: "Stage" },
                  { name: "is-closed",      type: "boolean", label: "Is Closed" },
                  { name: "owner-id",       type: "string",  label: "Owner ID" },
                  { name: "owner-name",     type: "string",  label: "Owner Name" },
                  { name: "account-id",     type: "string",  label: "Account ID" },
                  { name: "account-name",   type: "string",  label: "Account Name" },
                  { name: "location-name",  type: "string",  label: "Location Name" },
                  { name: "street",         type: "string",  label: "Street" },
                  { name: "city",           type: "string",  label: "City" },
                  { name: "state",          type: "string",  label: "State" },
                  { name: "postal-code",    type: "string",  label: "Postal Code" },
                  { name: "country",        type: "string",  label: "Country" },
                  {
                    name: "custom-attributes",
                    type: "object",
                    label: "Custom Attributes"
                  }
                ]
              },
              {
                name: "relationships",
            type: "object",
                properties: [
                  {
                    name: "account",
                    type: "object",
                    properties: [
                      {
                        name: "data",
                        type: "object",
                        properties: [
                          { name: "type", type: "string", label: "Type" },
                          { name: "id",   type: "string", label: "Account ID" }
                        ]
                      }
                    ]
                  },
                  {
                    name: "projects",
                    type: "array",
                    of: "object",
                    properties: [
                      {
                        name: "data",
                        type: "array",
                        of: "object",
                        properties: [
                          { name: "type", type: "string", label: "Type" },
                          { name: "id",   type: "string", label: "Project ID" }
                        ]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end,
    
      sample_output: lambda do |_connection, _input|
        {
          "data" => [
            {
            "id" => "123",
            "type" => "crm-opportunities",
            "attributes" => {
              "opportunity-id" => "OPP-123",
              "name" => "Sample Opportunity",
              "display-name" => "Sample Client / Sample Opportunity / OPP-123",
              "amount" => "10000.00",
              "stage" => "Proposal",
              "is-closed" => false,
              "owner-id" => "OWN-123",
              "owner-name" => "John Doe",
              "account-id" => "ACC-123",
              "account-name" => "Sample Client",
              "location-name" => "Main Office",
              "street" => "123 Main St",
              "city" => "San Francisco",
              "state" => "CA",
              "postal-code" => "94105",
              "country" => "US",
              "custom-attributes" => {
                  "custom_field_1" => "value1",
                  "custom_field_2" => "value2"
              }
            },
            "relationships" => {
              "account" => {
                "data" => {
                  "type" => "accounts",
                  "id" => "ACC-123"
                }
              },
              "projects" => {
                "data" => [
                  {
                    "type" => "projects",
                    "id" => "PRJ-123"
                  }
                ]
              }
            }
          }
          ]
        }
      end
    }, 
 
    list_clients: {
      title: "List Clients",
      subtitle: "List clients from ScopeStack",
      description: "List <span class='provider'>clients</span> from <span class='provider'>ScopeStack</span>",
      help: "Retrieves a list of all clients with their related data.",
      
      input_fields: lambda do |object_definitions|
        [
          {
            name: 'name',
            label: 'Client Name',
            hint: 'Filter clients by name (partial match)',
            optional: true
          },
          {
            name: 'domain',
            label: 'Domain',
            hint: 'Filter clients by domain (e.g., google.com) or identifier (e.g., client-123). If searching for a stored domain, use the same format it was stored in.',
            optional: true
          },
          {
            name: 'domain_is_url',
            label: 'Domain is a Web URL',
            type: 'string',
            control_type: 'select',
            optional: true,
            default: 'true',
            pick_list: [
              ['Yes', 'true'],
              ['No', 'false']
            ],
            hint: 'Select "Yes" if the domain field contains a full URL (e.g., https://www.example.com). The system will extract just the domain (example.com) for searching. Select "No" for plain text identifiers (no spaces allowed).'
          },
          {
            name: 'active',
            label: 'Active Status',
            type: 'string',
            control_type: 'select',
            optional: true,
            default: 'true',
            pick_list: [
              ['True', 'true'],
              ['False', 'false']
            ],
            hint: 'Filter by active status (defaults to true if not specified)'
          }
        ]
      end,
      
      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Validate input parameters
        if input['name'] && input['name'].strip.empty?
          error("Client name filter cannot be empty. Please provide a valid name or leave it blank.")
        end
        
        if input['domain'] && input['domain'].strip.empty?
          error("Domain filter cannot be empty. Please provide a valid domain or leave it blank.")
        end

        # Set up filters with includes
        filters = {
          "include" => "account,rate-table,contacts",
          "page[size]" => 100
        }
        
        # Add filter parameters if provided
        filters["filter[name]"] = input['name'].strip if input['name'].present?
        filters["filter[domain]"] = call('process_domain_field', input['domain'], input['domain_is_url']) if input['domain'].present?
        filters["filter[active]"] = input['active'] if input.key?('active')

        all_data = []
        current_page = 1
        has_more_pages = true

        while has_more_pages
          filters["page[number]"] = current_page
          
          response = get("/#{account_slug}/v1/clients")
            .params(filters)
            .after_error_response(/.*/) do |_code, body, _header, message|
              error("#{message}: #{body}")
            end

          # Add the current page's data to our collection
          all_data.concat(response['data'] || [])

          # Check if there are more pages
          total_pages = response.dig('meta', 'page-count') || 1
          has_more_pages = current_page < total_pages
          current_page += 1
        end

        # Format the response to include relationship IDs
        formatted_data = all_data.map do |client|
          client_data = client.dup
          if client_data['relationships']
            client_data['relationships'] = client_data['relationships'].transform_values do |rel|
              if rel['data'].is_a?(Array)
                rel['data'].map { |item| item['id'] }
              elsif rel['data'].is_a?(Hash)
                rel['data']['id']
              else
                nil
              end
            end
          end
          client_data
        end

        # Return the combined data
        {
          data: formatted_data,
          meta: {
            total_count: all_data.size
          }
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: 'data',
            label: 'Clients',
            type: 'array',
            of: 'object',
            properties: object_definitions['client']
          },
          {
            name: 'meta',
            label: 'Metadata',
            type: 'object',
            properties: [
              { 
                name: 'total_count',
                label: 'Total Count',
                type: 'integer'
              }
            ]
          }
        ]
      end,

      sample_output: lambda do |connection, input|
        {
          data: [
            {
              id: "123",
              type: "clients",
              attributes: {
                active: true,
                name: "Sample Client",
                "msa-date": "2024-03-25",
                domain: "example.com"
              },
              relationships: {
                account: ["456"],
                "rate-table": ["789"],
                contacts: ["101", "102"]
              }
            }
          ],
          meta: {
            total_count: 1
          }
        }
      end
    },

    list_products: {
      title: "List Products",
      subtitle: "List all products in an account",
      description: lambda do |_input, _picklist_label|
        "List all <span class='provider'>products</span> in " \
        "<span class='provider'>ScopeStack</span>"
      end,
      help: "Lists all products in your ScopeStack account. You can filter the results by various criteria including name, category, SKU, and more.",
      
      input_fields: lambda do |_object_definitions|
        [
              {
                name: "name",
            label: "Product Name",
                type: "string",
            hint: "Filter by product name",
                optional: true
              },
              {
            name: "category",
            label: "Category",
                type: "string",
            hint: "Filter by product category",
                optional: true
              },
              {
            name: "subcategory",
            label: "Subcategory",
                type: "string",
            hint: "Filter by product subcategory",
            optional: true 
              },
              {
            name: "sku",
            label: "SKU",
                type: "string",
            hint: "Filter by product SKU",
                optional: true
              },
              {
            name: "product_id",
            label: "Product ID",
                type: "string",
            hint: "Filter by product ID",
                optional: true
              },
              {
            name: "manufacturer_name",
            label: "Manufacturer Name",
                type: "string",
            hint: "Filter by manufacturer name",
                optional: true
              },
              {
            name: "manufacturer_part_number",
            label: "Manufacturer Part Number",
                type: "string",
            hint: "Filter by manufacturer part number",
            optional: true 
              },
              {
            name: "vendor_name",
            label: "Vendor Name",
                type: "string",
            hint: "Filter by vendor name",
                optional: true
              },
              { 
            name: "active",
            label: "Active Status",
            type: "boolean",
            control_type: "checkbox",
            hint: "Filter by active status. Checked for active products, unchecked for archived products.",
                optional: true,
            default: true
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account slug from environment property or connection
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        # Build filter parameters
        filter_params = {}
        filter_params['filter[name]'] = input['name'] if input['name'].present?
        filter_params['filter[category]'] = input['category'] if input['category'].present?
        filter_params['filter[subcategory]'] = input['subcategory'] if input['subcategory'].present?
        filter_params['filter[sku]'] = input['sku'] if input['sku'].present?
        filter_params['filter[product-id]'] = input['product_id'] if input['product_id'].present?
        filter_params['filter[manufacturer-name]'] = input['manufacturer_name'] if input['manufacturer_name'].present?
        filter_params['filter[manufacturer-part-number]'] = input['manufacturer_part_number'] if input['manufacturer_part_number'].present?
        filter_params['filter[vendor-name]'] = input['vendor_name'] if input['vendor_name'].present?
        filter_params['filter[active]'] = input['active'] if input['active'].present?

        # Set a reasonable page size for each request
        filter_params["page[size]"] = 100

        all_data = []
        current_page = 1
        has_more_pages = true

        while has_more_pages
          filter_params["page[number]"] = current_page
          
          response = get("/#{account_slug}/v1/products")
            .params(filter_params)
                            .after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end

          # Add the current page's data to our collection
          all_data.concat(response['data'] || [])

          # Check if there are more pages
          total_pages = response.dig('meta', 'page-count') || 1
          has_more_pages = current_page < total_pages
          current_page += 1
        end

        # Return the combined data
        {
          data: all_data,
          meta: {
            total_count: all_data.size
          }
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: 'data',
            label: 'Products',
            type: 'array',
            of: 'object',
            properties: object_definitions['product']
          },
          {
            name: 'meta',
            label: 'Metadata',
            type: 'object',
            properties: [
              {
                name: 'total_count',
                label: 'Total Count',
                type: 'integer'
              }
            ]
          }
        ]
      end,

      sample_output: lambda do |connection, input|
        # Get a sample product to show the structure
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        response = get("/#{account_slug}/v1/products")
          .params(
            "page[size]" => 1
          )
          .after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end

        {
          data: response['data'] || [],
          meta: {
            total_count: response.dig('meta', 'total_count') || 1
          }
        }
      end
    },
 
    create_or_update_product: {
      title: "Create or Update Product",
      subtitle: "Creates a new product or updates an existing one in ScopeStack",
      description: "Create a new product or update an existing one in <span class='provider'>ScopeStack</span>",
      help: {
        body: "This action creates or updates a product in ScopeStack based on the selected matching strategy:\n\n" \
              "1. Match by ID: Updates the product with the specified ScopeStack ID\n" \
              "2. Match by Name: Updates an existing product with the same name or creates a new one\n" \
              "3. Match by SKU: Updates an existing product with the same SKU or creates a new one\n" \
              "4. Match by Product ID: Updates an existing product with the same Product ID or creates a new one\n" \
              "5. Match by Manufacturer Part Number: Updates an existing product with the same MPN or creates a new one\n\n" \
              "This ensures that products are properly managed in ScopeStack.",
        learn_more_url: "https://docs.scopestack.io/api/#tag/Products",
        learn_more_text: "Products API Documentation"
      },
    
      input_fields: lambda do |_object_definitions, connection|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Create fields array
        fields = [
          {
            name: 'matching_strategy',
            label: 'Matching Strategy',
            type: 'string',
            control_type: 'select',
            pick_list: [
              ['Don\'t match, create a new product', 'create_new'],
              ['Match by ScopeStack ID', 'id'],
              ['Match by Name', 'name'],
              ['Match by SKU', 'sku'],
              ['Match by Product ID', 'product_id'],
              ['Match by Manufacturer Part Number', 'manufacturer_part_number']
            ],
            optional: false,
            hint: 'Select how to match existing products or create a new one'
          },
          {
            name: 'id',
            label: 'ScopeStack ID',
            type: 'string',
          optional: true,
            hint: 'The ScopeStack ID of the product to update'
          },
          {
            name: 'name',
            label: 'Name',
            type: 'string',
            optional: false,
            hint: 'Product name'
          },
          {
            name: 'description',
            label: 'Description',
            type: 'string',
                optional: true
              },
              { 
            name: 'sku',
            label: 'SKU',
            type: 'string',
                optional: true
              },
              { 
            name: 'product_id',
            label: 'Product ID',
            type: 'string',
                optional: true
              },
              { 
            name: 'manufacturer_part_number',
            label: 'Manufacturer Part Number',
            type: 'string',
                optional: true
              },
              { 
            name: 'unit_of_measure',
            label: 'Unit of Measure',
            type: 'string',
                optional: true
              },
              { 
            name: 'category',
            label: 'Category',
            type: 'string',
                optional: true
              },
              { 
            name: 'subcategory',
            label: 'Subcategory',
            type: 'string',
                optional: true
              },
              { 
            name: 'billing_frequency',
            label: 'Billing Frequency',
            type: 'string',
            control_type: 'select',
            pick_list: [
              ['One Time', 'one_time'],
              ['Monthly', 'monthly'],
              ['Quarterly', 'quarterly'],
              ['Annually', 'annually']
            ],
                optional: true
              },
              { 
            name: 'unit_price_group',
            label: 'Unit Price',
            type: 'object',
            properties: [
              {
                name: 'unit_price',
                label: 'Unit Price',
                type: 'number',
                control_type: 'number',
                optional: true,
                hint: 'Base price per unit. If either Unit Price or Unit Cost is provided, this will take precedence over List Price options and clear any existing List Price values.'
              },
              {
                name: 'unit_cost',
                label: 'Unit Cost',
                type: 'number',
                control_type: 'number',
                optional: true,
                hint: 'Cost per unit. If either Unit Price or Unit Cost is provided, this will take precedence over List Price options and clear any existing List Price values.'
              }
            ]
          },
          {
            name: 'list_price_group',
            label: 'List Price',
            type: 'object',
            properties: [
              {
                name: 'list_price',
                label: 'List Price',
                type: 'number',
                control_type: 'number',
            optional: true,
                hint: 'Customer-facing price. Only used if no Unit Price or Unit Cost is provided.'
              },
              {
                name: 'markup',
                label: 'Markup %',
                  type: 'string',
                  control_type: 'text',
            optional: true,
                hint: 'Markup percentage (e.g., "10%" or "10")'
              },
              {
                name: 'vendor_discount',
                label: 'Vendor Discount %',
                type: 'string',
                control_type: 'text',
                optional: true,
                hint: 'Vendor discount percentage (e.g., "5%" or "5")'
              },
              {
                name: 'vendor_rebate',
                label: 'Vendor Rebate %',
                type: 'string',
                control_type: 'text',
            optional: true,
                hint: 'Vendor rebate percentage (e.g., "3%" or "3")'
              }
            ]
          }
        ]
    
        # Add dynamic project variables
        begin
        project_variables_response = get("/#{account_slug}/v1/project-variables")
            .params(filter: { 'variable-context': 'product' })
                                     .headers('Accept': 'application/vnd.api+json')
                                     .after_error_response(/.*/) do |_code, body, _header, message|
                                       error("Failed to fetch project variables: #{message}: #{body}")
                                     end

          if project_variables_response['data'].any?
        project_variables_response['data'].each do |var|
              attrs = var['attributes']
              var_name = attrs['name']
              var_label = attrs['label']
              var_hint = attrs['description'] || "Project variable: #{var_label}"
    
              dynamic_field = {
                name: "var_#{var_name}",
                label: var_label,
                hint: var_hint,
                optional: !attrs['required']
              }
    
              case attrs['variable-type']
          when 'number'
                dynamic_field[:type] = 'number'
                dynamic_field[:control_type] = 'number'
          when 'date'
                dynamic_field[:type] = 'date'
                dynamic_field[:control_type] = 'date'
              when 'select'
                dynamic_field[:type] = 'string'
                dynamic_field[:control_type] = 'select'
                dynamic_field[:pick_list] = attrs['select-options']&.map { |opt| [opt['label'], opt['value']] } || []
              else
                dynamic_field[:type] = 'string'
                dynamic_field[:control_type] = 'text'
              end
    
              fields << dynamic_field
            end
          end
        rescue StandardError => e
          puts "Error fetching project variables: #{e.message}"
        end
    
        fields
      end,
    
      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        account_id = account_info[:account_id]
    
        # Prepare payload for new product creation
        payload = {
          data: {
            type: "products",
            attributes: {
              "active": true
            },
            relationships: {
              account: {
                data: {
                  type: "accounts",
                  id: account_id.to_s
                }
              }
            }
          }
        }

        # Add basic fields if provided
        payload[:data][:attributes]["name"] = input['name'] if input['name'].present?
        payload[:data][:attributes]["description"] = input['description'] if input['description'].present?
        payload[:data][:attributes]["sku"] = input['sku'] if input['sku'].present?
        payload[:data][:attributes]["product-id"] = input['product_id'] if input['product_id'].present?
        payload[:data][:attributes]["manufacturer-part-number"] = input['manufacturer_part_number'] if input['manufacturer_part_number'].present?
        payload[:data][:attributes]["unit-of-measure"] = input['unit_of_measure'] if input['unit_of_measure'].present?
        payload[:data][:attributes]["category"] = input['category'] if input['category'].present?
        payload[:data][:attributes]["subcategory"] = input['subcategory'] if input['subcategory'].present?
        payload[:data][:attributes]["billing-frequency"] = input['billing_frequency'] if input['billing_frequency'].present?
    
        # Handle unit price group
        if input['unit_price_group'].present?
          payload[:data][:attributes]["unit-price"] = input['unit_price_group']['unit_price'] if input['unit_price_group']['unit_price'].present?
          payload[:data][:attributes]["unit-cost"] = input['unit_price_group']['unit_cost'] if input['unit_price_group']['unit_cost'].present?
          
          # Clear list price group values when using unit price method
          payload[:data][:attributes]["list-price"] = ""
          payload[:data][:attributes]["markup"] = ""
          payload[:data][:attributes]["vendor-discount"] = ""
          payload[:data][:attributes]["vendor-rebate"] = ""
        end
    
        # Handle list price group (only if unit price group is not provided)
        if input['list_price_group'].present? && !input['unit_price_group'].present?
          if input['list_price_group']['list_price'].present?
            payload[:data][:attributes]["list-price"] = input['list_price_group']['list_price']
            
            # Set percentage values to 0 if list price is provided but percentages are not
            payload[:data][:attributes]["vendor-discount"] = if input['list_price_group']['vendor_discount'].present?
              input['list_price_group']['vendor_discount'].to_s.gsub('%', '').to_f
            else
              0.0
            end
            
            payload[:data][:attributes]["vendor-rebate"] = if input['list_price_group']['vendor_rebate'].present?
              input['list_price_group']['vendor_rebate'].to_s.gsub('%', '').to_f
            else
              0.0
            end
            
            payload[:data][:attributes]["markup"] = if input['list_price_group']['markup'].present?
              input['list_price_group']['markup'].to_s.gsub('%', '').to_f
            else
              0.0
          end
        end

          # Clear unit price and unit cost when using list price method
          payload[:data][:attributes]["unit-price"] = ""
          payload[:data][:attributes]["unit-cost"] = ""
        end
    
        # Process project variables
        project_variables = input.keys
                               .select { |k| k.start_with?('var_') }
                               .map do |k|
                                 var_name = k.sub('var_', '')
                                 { name: var_name, value: input[k] }
                               end.reject { |v| v[:value].nil? }

        payload[:data][:attributes]["project-variables"] = project_variables if project_variables.any?
    
        # Handle different matching strategies
        case input['matching_strategy']
        when 'create_new'
          # Create new product without searching
          response = post("/#{account_slug}/v1/products")
                    .headers('Content-Type': 'application/vnd.api+json',
                            'Accept': 'application/vnd.api+json')
            .payload(payload)
            .after_error_response(/.*/) do |_code, body, _header, message|
                      error("Failed to create product: #{message}: #{body}")
                    end
        when 'id'
          if input['id'].blank?
            error("Product ID is required when using 'Match by ID' strategy")
          end
          
          # Verify the product exists
          get_response = get("/#{account_slug}/v1/products/#{input['id']}")
                        .headers('Accept': 'application/vnd.api+json')
                        .after_error_response(/.*/) do |_code, body, _header, message|
                          error("Failed to fetch product: #{message}: #{body}")
                        end
    
          if get_response['data'].nil?
            error("Product with ID #{input['id']} not found")
          end
    
          # Update existing product
          payload[:data][:id] = input['id'].to_s
          response = patch("/#{account_slug}/v1/products/#{input['id']}")
                    .headers('Content-Type': 'application/vnd.api+json',
                            'Accept': 'application/vnd.api+json')
                    .payload(payload)
                    .after_error_response(/.*/) do |_code, body, _header, message|
                      error("Failed to update product: #{message}: #{body}")
            end
        else
          # For other matching strategies, search for existing product
          search_field = case input['matching_strategy']
                        when 'name' then 'name'
                        when 'sku' then 'sku'
                        when 'product_id' then 'product-id'
                        when 'manufacturer_part_number' then 'manufacturer-part-number'
                        end
    
          search_value = input[search_field.gsub('-', '_')]
          
          if search_value.blank?
            error("#{search_field.gsub('-', ' ').capitalize} is required when using '#{input['matching_strategy']}' matching strategy")
          end
    
          # Search for existing product
          search_response = get("/#{account_slug}/v1/products")
                              .headers('Accept': 'application/vnd.api+json')
                           .params(filter: { search_field => search_value })
                              .after_error_response(/.*/) do |_code, body, _header, message|
                             error("Failed to search for product: #{message}: #{body}")
                           end
    
          if search_response['data'].any?
            # Check if multiple products were found
            if search_response['data'].size > 1
              product_ids = search_response['data'].map { |p| p['id'] }.join(', ')
              error("Multiple products found with the same #{search_field.gsub('-', ' ')} (#{search_value}). Please use 'Match by ScopeStack ID' strategy and specify the exact product ID. Found product IDs: #{product_ids}")
            end
            
            # Update existing product
            existing_product = search_response['data'].first
            payload[:data][:id] = existing_product['id'].to_s
            response = patch("/#{account_slug}/v1/products/#{existing_product['id']}")
                      .headers('Content-Type': 'application/vnd.api+json',
                              'Accept': 'application/vnd.api+json')
            .payload(payload)
            .after_error_response(/.*/) do |_code, body, _header, message|
                        error("Failed to update product: #{message}: #{body}")
              end
          else
            # Create new product
            response = post("/#{account_slug}/v1/products")
                      .headers('Content-Type': 'application/vnd.api+json',
                              'Accept': 'application/vnd.api+json')
              .payload(payload)
              .after_error_response(/.*/) do |_code, body, _header, message|
                        error("Failed to create product: #{message}: #{body}")
              end
            end
        end

        response['data']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['product']
      end,

      sample_output: lambda do |connection, input|
        # Get a sample product to show the structure
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        # Get a sample product
        response = get("/#{account_slug}/v1/products")
                  .params(limit: 1)
                  .headers('Accept': 'application/vnd.api+json')
                  .after_error_response(/.*/) do |_code, body, _header, message|
                    error("Failed to fetch sample product: #{message}: #{body}")
                  end
        
        response['data'].first || {}
      end
    },
 
    list_projects_by_crm_opportunity: {
      title: 'List Projects by CRM Opportunity',
      subtitle: 'Retrieve all projects linked to a specific CRM opportunity',
      description: 'List <span class="provider">Projects</span> linked to a specific <span class="provider">CRM Opportunity</span> in <span class="provider">ScopeStack</span>',
      help: 'This action retrieves all projects that are linked to a specific CRM opportunity in ScopeStack.',
     
      input_fields: lambda do |object_definitions|
        [
          {
            name: 'crm_opportunity_id',
            label: 'CRM Opportunity ID',
            optional: false,
            hint: 'The ID of the CRM opportunity to find linked projects for'
          }
        ]
      end,

      execute: lambda do |connection, input|
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # First, get the CRM opportunity to verify it exists and get its relationships
        crm_opportunity = get("/#{account_slug}/v1/crm-opportunities")
                  .params(
                          filter: { 'opportunity-id': input['crm_opportunity_id'] }
                  )
                  .headers('Accept': 'application/vnd.api+json')
                                .after_error_response(/.*/) do |_code, body, _header, message|
                          error("Failed to fetch CRM opportunity: #{message}: #{body}")
                        end

        # If no CRM opportunity found, return empty array
        return { data: [] } if crm_opportunity['data'].empty?

        # Get the CRM opportunity ID from the response
        crm_opportunity_id = crm_opportunity['data'].first['id']

        # Use the relationships endpoint to get linked projects
        projects_response = get("/#{account_slug}/v1/crm-opportunities/#{crm_opportunity_id}/projects")
                          .headers('Accept': 'application/vnd.api+json')
                          .after_error_response(/.*/) do |_code, body, _header, message|
                            error("Failed to fetch projects: #{message}: #{body}")
                          end

        {
          data: projects_response['data'] || []
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: 'data',
            type: 'array',
            of: 'object',
            properties: object_definitions['project']
          }
        ]
      end,

      sample_output: lambda do |connection, input|
        # Get a sample project to show the structure
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        response = get("/#{account_slug}/v1/projects")
                  .params(limit: 1)
                  .headers('Accept': 'application/vnd.api+json')
                  .after_error_response(/.*/) do |_code, body, _header, message|
                    error("Failed to fetch sample project: #{message}: #{body}")
                  end
        
        {
          data: [response['data'].first || {}]
        }
      end
    },


    get_entity_variable: {
      title: "Get User Defined Field/Entity Variable",
      subtitle: "Get a specific project variable value for any entity type",
      description: "Get <span class='provider'>project variable</span> value from <span class='provider'>ScopeStack</span> for projects, contacts, locations, project governance, and other entities",
      help: "Retrieves the value of a specific project variable for any entity type (projects, contacts, locations, project governance, etc.). Returns whether the entity has a value for that variable, the value itself, and the variable type.",
     
      input_fields: lambda do |object_definitions, connection|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Fetch all project variables from the API (no filter to get all contexts)
        project_variables_response = get("/#{account_slug}/v1/project-variables")
                                     .headers('Accept': 'application/vnd.api+json')
                                     .after_error_response(/.*/) do |code, body, _header, message|
                                       case code
                                       when 401, 403
                                         error("Authentication failed or insufficient permissions to access project variables. Please check your credentials.")
                                       when 500..599
                                         error("ScopeStack server error occurred while fetching project variables. Please try again later.")
                                       else
                                         error("Failed to fetch project variables: #{message}. Response: #{body}")
                                       end
                                     end

        all_vars = project_variables_response['data'] || []

        # Create the variable picklist with context prefixes
        if all_vars.empty?
          variable_picklist = [["No project variables found", "no_variables"]]
        else
          variable_picklist = all_vars.map do |var|
            context = var.dig('attributes', 'variable-context') || 'unknown'
            label = var.dig('attributes', 'label') || var.dig('attributes', 'name') || "Variable #{var['id']}"
            name = var.dig('attributes', 'name')
            
            # Create display label with context prefix
            context_display = case context
                             when 'project'
                               'Project'
                             when 'service_location'
                               'Location'
                             when 'project_contact'
                               'Contact'
                             when 'product'
                               'Product'
                             when 'crm_opportunity'
                               'CRM Opportunity'
                             when 'governance'
                               'Project Governance'
                             when 'client'
                               'Client'
                             else
                               context.humanize
                             end
            
            display_label = "#{context_display} / #{label}"
            [display_label, "#{context}:#{name}"]
          end.compact
        end

        [
          {
            name: 'variable_identifier',
            label: 'User Defined Field/Entity Variable',
            type: 'string',
            control_type: 'select',
            pick_list: variable_picklist,
            optional: false,
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'variable_identifier',
              label: 'User Defined Field/Entity Variable Identifier',
              type: 'string',
              control_type: 'text',
              optional: false,
              toggle_hint: 'Use custom value',
              hint: 'Enter the identifier in format "context:variable_name" (e.g., "project:my_variable", "contact:contact_field")'
            }
          },
          {
            name: 'entity_id',
            label: 'Entity ID',
            type: 'string',
            control_type: 'text',
            optional: false,
            hint: 'Enter the ID of the entity to retrieve the variable value from'
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        entity_id = input['entity_id']
        variable_identifier = input['variable_identifier']

        # Parse the variable identifier to get context and variable name
        if variable_identifier.include?(':')
          context, variable_name = variable_identifier.split(':', 2)
        else
          error("Invalid variable identifier format. Expected 'context:variable_name' (e.g., 'project:my_variable')")
        end

        # Map context to entity type
        entity_type = case context
                     when 'project'
                       'project'
                     when 'service_location'
                       'project_location'
                     when 'project_contact'
                       'project_contact'
                     when 'product'
                       'product'
                     when 'crm_opportunity'
                       'crm_opportunity'
                     when 'governance'
                       'project_governance'
                     when 'client'
                       'client'
                     else
                       error("Unsupported variable context: #{context}")
                     end

        # Determine the API endpoint based on entity type
        endpoint = case entity_type
                  when 'project'
                    "/#{account_slug}/v1/projects/#{entity_id}"
                  when 'project_contact'
                    "/#{account_slug}/v1/project-contacts/#{entity_id}"
                  when 'project_location'
                    "/#{account_slug}/v1/project-locations/#{entity_id}"
                  when 'product'
                    "/#{account_slug}/v1/products/#{entity_id}"
                  when 'crm_opportunity'
                    "/#{account_slug}/v1/crm-opportunities/#{entity_id}"
                  when 'project_governance'
                    "/#{account_slug}/v1/project-governances/#{entity_id}"
                  when 'client'
                    "/#{account_slug}/v1/clients/#{entity_id}"
                  else
                    error("Unsupported entity type: #{entity_type}")
                  end

        # Get entity details
        response = get(endpoint)
                   .headers('Accept': 'application/vnd.api+json')
                   .after_error_response(/.*/) do |_code, body, _header, message|
                     error("Failed to fetch #{entity_type}: #{message}: #{body}")
                   end

        entity_data = response['data']
        
        # Extract variables based on entity type - clients use 'user-defined-fields', others use 'project-variables'
        # Both represent the same concept: user defined fields/variables for that entity context
        entity_variables = if entity_type == 'client'
                            entity_data.dig('attributes', 'user-defined-fields') || []
                        else
                            entity_data.dig('attributes', 'project-variables') || []
                          end

        # Find the specific variable
        target_variable = entity_variables.find { |var| var['name'] == variable_name }

        # Extract variable information from the entity data
        if target_variable
          variable_label = target_variable['label']
          variable_type = target_variable['variable_type']
          required = target_variable['required']
          raw_value = target_variable['value']
          select_options = target_variable['select_options'] || []
          
          # Handle empty strings as null values
          if raw_value.nil? || raw_value == ""
            value = nil
            has_value = false
          else
            value = raw_value
            has_value = true
          end
          
          # Find the display key for select variables
          key = ""
          if select_options.any? && has_value
            matching_option = select_options.find { |opt| opt['value'] == raw_value }
            key = matching_option['key'] if matching_option
          end
        else
          variable_label = variable_name
          variable_type = 'unknown'
          required = false
          value = nil
          has_value = false
          key = ""
        end

        # Get entity name based on type
        entity_name = case entity_type
                     when 'project'
                       entity_data.dig('attributes', 'project-name')
                     when 'project_contact'
                       entity_data.dig('attributes', 'name')
                     when 'project_location'
                       entity_data.dig('attributes', 'name')
                     when 'product'
                       entity_data.dig('attributes', 'name')
                     when 'crm_opportunity'
                       entity_data.dig('attributes', 'name')
                     when 'project_governance'
                       entity_data.dig('attributes', 'description')
                     when 'client'
                       entity_data.dig('attributes', 'name')
                     else
                       "Unknown Entity"
                     end

        # Prepare the result
        result = {
          entity_id: entity_id,
          entity_type: entity_type,
          entity_name: entity_name,
          variable_name: variable_name,
          variable_label: variable_label,
          variable_type: variable_type,
          required: required,
          has_value: has_value,
          value: value,
          key: key
        }

        result
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: "entity_id", type: "integer", label: "Entity ID" },
          { name: "entity_type", type: "string", label: "Entity Type" },
          { name: "entity_name", type: "string", label: "Entity Name" },
          { name: "variable_name", type: "string", label: "Variable Name" },
          { name: "variable_label", type: "string", label: "Variable Label" },
          { name: "variable_type", type: "string", label: "Variable Type" },
          { name: "required", type: "boolean", label: "Required" },
          { name: "has_value", type: "boolean", label: "Has Value" },
          { name: "value", type: "string", label: "Value" },
          { name: "key", type: "string", label: "Display Key", hint: "For select variables, this is the human-readable display text. For non-select variables, this will be null." }
        ]
      end,

      sample_output: lambda do |connection, input|
        # Return a static sample output
        {
          entity_id: "123",
          entity_type: "project",
          entity_name: "Sample Project",
          variable_name: "sample_variable",
          variable_label: "Sample Variable",
          variable_type: "text",
          required: false,
          has_value: true,
          value: "Sample Value",
          key: ""
        }
      end
    },

    list_project_phases: {
      title: "List Project Phases",
      subtitle: "Get all phases for a specific project",
      description: "List <span class='provider'>project phases</span> in <span class='provider'>ScopeStack</span>",
      help: "Retrieves all active phases for a specific project. This action automatically handles pagination to return all phases.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "project_id",
            label: "Project ID",
            type: "string",
            control_type: "number",
            optional: false,
            hint: "Enter the ID of the project to get phases for",
            sticky: true
          },
          {
            name: "sort_order",
            label: "Sort Order",
            type: "string",
            control_type: "select",
            pick_list: [
              ["First to Last (1, 2, 3...)", "first_to_last"],
              ["Last to First (...3, 2, 1)", "last_to_first"]
            ],
            default: "first_to_last",
            optional: false,
            hint: "Choose the order to sort results by position. 'First to Last' shows position 1 first, 'Last to First' shows the highest position first."
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        # Validate project_id is a number
        project_id = input['project_id'].to_s.strip
        unless project_id.match?(/^\d+$/)
          error("Project ID must be a valid number")
        end

        # Set up filters and pagination
        filters = {
          "filter[active]" => "true",
          "filter[project]" => project_id,
          "page[size]" => 100
        }

        all_data = []
        current_page = 1
        has_more_pages = true

        while has_more_pages
          filters["page[number]"] = current_page
          
          response = get("/#{account_slug}/v1/project-phases")
            .params(filters)
            .after_error_response(/.*/) do |code, body, _header, message|
              case code
              when 404
                error("Project not found with ID: #{project_id}")
              when 401, 403
                error("Authentication failed or insufficient permissions: #{message}")
              else
                error("Failed to fetch project phases (#{code}): #{message}: #{body}")
              end
            end
          
          # Add the current page's data to our collection
          all_data.concat(response['data'] || [])

          # Check if there are more pages
          total_pages = response.dig('meta', 'page-count') || 1
          has_more_pages = current_page < total_pages
          current_page += 1
        end

        # Sort by position attribute
        sorted_data = all_data.sort_by do |phase|
          phase.dig('attributes', 'position') || 0
        end
        
        # Reverse if last_to_first is selected
        sorted_data = sorted_data.reverse if input['sort_order'] == 'last_to_first'

        # Return the combined data
        {
          data: sorted_data,
          meta: {
            total_count: sorted_data.size
          }
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: "data",
            type: "array",
            of: "object",
            properties: object_definitions['project_phase']
          },
          {
            name: "meta",
            type: "object",
            properties: [
              { name: "total_count", type: "integer", label: "Total Count" }
            ]
          }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        {
          "data" => [
            {
              "id" => "602417",
              "type" => "project-phases",
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-phases/602417"
              },
              "attributes" => {
                "active" => true,
                "name" => "Plan",
                "sow-language" => "planning_language",
                "position" => 1
              },
              "relationships" => {
                "project" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-phases/602417/relationships/project",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-phases/602417/project"
                  }
                },
                "phase" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-phases/602417/relationships/phase",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-phases/602417/phase"
                  }
                }
              }
            },
            {
              "id" => "602418",
              "type" => "project-phases",
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-phases/602418"
              },
              "attributes" => {
                "active" => true,
                "name" => "Design",
                "sow-language" => "design_language",
                "position" => 2
              },
              "relationships" => {
                "project" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-phases/602418/relationships/project",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-phases/602418/project"
                  }
                },
                "phase" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-phases/602418/relationships/phase",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-phases/602418/phase"
                  }
                }
              }
            }
          ],
          "meta" => {
            "total_count" => 2
          }
        }
      end
    },

    list_project_resources: {
      title: "List Project Resources",
      subtitle: "Get all resources for a specific project",
      description: "List <span class='provider'>project resources</span> in <span class='provider'>ScopeStack</span>",
      help: "Retrieves all resources for a specific project. Optionally filter by active status. This action automatically handles pagination to return all resources.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "project_id",
            label: "Project ID",
            type: "integer",
            optional: false,
            hint: "Enter the ID of the project to get resources for",
            sticky: true
          },
          {
            name: "active",
            label: "Active Only",
            type: "boolean",
            control_type: "checkbox",
            optional: true,
            hint: "If checked, only return active resources. If unchecked or not specified, returns all resources.",
            sticky: true
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        # Validate project_id is a number
        project_id = input['project_id'].to_s.strip
        unless project_id.match?(/^\d+$/)
          error("Project ID must be a valid number")
        end

        # Set up filters and pagination
        # Note: When using nested endpoint /projects/{id}/project-resources, don't include filter[project]
        filters = {
          "include" => "project",
          "page[size]" => 100
        }

        # Add active filter if specified
        if input['active'] == true
          filters["filter[active]"] = "true"
        end

        all_data = []
        current_page = 1
        has_more_pages = true

        while has_more_pages
          filters["page[number]"] = current_page
          
          response = get("/#{account_slug}/v1/projects/#{project_id}/project-resources")
            .params(filters)
            .after_error_response(/.*/) do |code, body, _header, message|
              case code
              when 404
                error("Project not found with ID: #{project_id}")
              when 401, 403
                error("Authentication failed or insufficient permissions: #{message}")
              else
                error("Failed to fetch project resources (#{code}): #{message}: #{body}")
              end
            end
          
          # Add the current page's data to our collection
          all_data.concat(response['data'] || [])

          # Check if there are more pages
          total_pages = response.dig('meta', 'page-count') || 1
          has_more_pages = current_page < total_pages
          current_page += 1
        end

        # Return the combined data
        {
          data: all_data,
          meta: {
            total_count: all_data.size
          }
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: "data",
            type: "array",
            of: "object",
            properties: object_definitions['project_resource']
          },
          {
            name: "meta",
            type: "object",
            properties: [
              { name: "total_count", type: "integer", label: "Total Count" }
            ]
          }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        {
          "data" => [
            {
              "id" => "275828",
              "type" => "project-resources",
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-resources/275828"
              },
              "attributes" => {
                "active" => true,
                "name" => "Engineer",
                "external-name" => nil,
                "extended-name" => "Engineer",
                "description" => nil,
                "total-hours" => "23.0",
                "hourly-rate" => "150.0",
                "hourly-cost" => "100.0",
                "expense-rate" => "100.0",
                "code" => nil,
                "resource" => {
                  "resource_type" => "resources",
                  "resource_id" => 15866,
                  "name" => "Engineer",
                  "hourly_rate" => "150.0",
                  "account_id" => 1197,
                  "hourly_cost" => "100.0",
                  "status" => 0,
                  "deleted_at" => nil,
                  "external_name" => nil,
                  "description" => nil,
                  "default" => false
                }
              },
              "relationships" => {
                "project" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-resources/275828/relationships/project",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-resources/275828/project"
                  },
                  "data" => {
                    "type" => "projects",
                    "id" => "87343"
                  }
                },
                "resource" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-resources/275828/relationships/resource",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-resources/275828/resource"
                  }
                },
                "line-of-business" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-resources/275828/relationships/line-of-business",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-resources/275828/line-of-business"
                  }
                }
              }
            }
          ],
          "meta" => {
            "total_count" => 1
          }
        }
      end
    },

    list_project_governances: {
      title: "List Project Governances",
      subtitle: "Get all governances for a specific project",
      description: "List <span class='provider'>project governances</span> in <span class='provider'>ScopeStack</span>",
      help: "Retrieves all governances for a specific project. Optionally filter by active status and include related data. This action automatically handles pagination to return all governances.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "project_id",
            label: "Project ID",
            type: "string",
            control_type: "number",
            optional: false,
            hint: "Enter the ID of the project to get governances for",
            sticky: true
          },
          {
            name: "active",
            label: "Active Only",
            type: "boolean",
            control_type: "checkbox",
            optional: true,
            hint: "If checked, only return active governances. If unchecked or not specified, returns all governances.",
            sticky: true
          },
          {
            name: "includes",
            label: "Include Related Data",
            type: "object",
            properties: [
              {
                name: "include_resource",
                label: "Resource",
                control_type: "checkbox",
                type: "boolean",
                optional: true,
                sticky: true,
                hint: "Include resource information"
              },
              {
                name: "include_project_phase",
                label: "Project Phase",
                control_type: "checkbox",
                type: "boolean",
                optional: true,
                sticky: true,
                hint: "Include project phase information"
              },
              {
                name: "include_project_resource",
                label: "Project Resource",
                control_type: "checkbox",
                type: "boolean",
                optional: true,
                sticky: true,
                hint: "Include project resource information"
              },
              {
                name: "include_project",
                label: "Project",
                control_type: "checkbox",
                type: "boolean",
                optional: true,
                sticky: true,
                hint: "Include project information"
              },
              {
                name: "include_service_category",
                label: "Service Category",
                control_type: "checkbox",
                type: "boolean",
                optional: true,
                sticky: true,
                hint: "Include service category information"
              }
            ]
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        # Validate project_id is a number
        project_id = input['project_id'].to_s.strip
        unless project_id.match?(/^\d+$/)
          error("Project ID must be a valid number")
        end

        # Set up filters and pagination
        filters = {
          "filter[project]" => project_id,
          "page[size]" => 100
        }

        # Add active filter if specified
        if input['active'] == true
          filters["filter[active]"] = "true"
        end

        # Build includes array from checkboxes
        includes = []
        includes << 'resource' if input.dig('includes', 'include_resource')
        includes << 'project-phase' if input.dig('includes', 'include_project_phase')
        includes << 'project-resource' if input.dig('includes', 'include_project_resource')
        includes << 'project' if input.dig('includes', 'include_project')
        includes << 'service-category' if input.dig('includes', 'include_service_category')
        
        # Add includes to filters if any are selected
        filters["include"] = includes.join(',') if includes.any?

        all_data = []
        current_page = 1
        has_more_pages = true

        while has_more_pages
          filters["page[number]"] = current_page
          
          response = get("/#{account_slug}/v1/project-governances")
            .params(filters)
            .after_error_response(/.*/) do |code, body, _header, message|
              case code
              when 404
                error("Project not found with ID: #{project_id}")
              when 401, 403
                error("Authentication failed or insufficient permissions: #{message}")
              else
                error("Failed to fetch project governances (#{code}): #{message}: #{body}")
              end
            end
          
          # Add the current page's data to our collection
          all_data.concat(response['data'] || [])

          # Check if there are more pages
          total_pages = response.dig('meta', 'page-count') || 1
          has_more_pages = current_page < total_pages
          current_page += 1
        end

        # Always fetch project-resource and standard resource information
        project_resources_map = {}
        governance_to_project_resource_map = {} # Map governance_id -> project_resource_id
        # Collect all unique project-resource IDs from governances
        project_resource_ids = []
        all_data.each do |governance|
          governance_id = governance['id']
          # Try to get project-resource ID from relationships data first
          project_resource_data = governance.dig('relationships', 'project-resource', 'data')
          project_resource_id = nil
          
          if project_resource_data && project_resource_data['id']
            project_resource_id = project_resource_data['id']
          else
            # If not in data, try to fetch from the related link
            project_resource_link = governance.dig('relationships', 'project-resource', 'links', 'related') || 
                                   governance.dig('relationships', 'project-resource', 'links', 'self')
            if project_resource_link && governance_id
              begin
                # Extract just the path portion from the URL
                uri = URI.parse(project_resource_link)
                path = uri.path
                
                # Fetch the project-resource from the related endpoint
                pr_response = get(path)
                  .headers('Accept': 'application/vnd.api+json')
                  .after_error_response(/.*/) do |code, body, _header, message|
                    puts "Warning: Could not fetch project-resource from link for governance #{governance_id}: #{code} - #{message}"
                    nil
                  end
                
                if pr_response && pr_response['data']
                  project_resource_id = pr_response['data']['id']
                end
              rescue => e
                puts "Warning: Could not fetch project-resource from link for governance #{governance_id}: #{e.message}"
              end
            end
          end
          
          # Store the mapping for this governance
          if project_resource_id.present?
            governance_to_project_resource_map[governance_id] = project_resource_id
            project_resource_ids << project_resource_id unless project_resource_ids.include?(project_resource_id)
          end
        end

        # Fetch project-resource details for each unique ID
        standard_resource_ids = []
        project_resource_ids.each do |resource_id|
          begin
            resource_response = get("/#{account_slug}/v1/project-resources/#{resource_id}")
              .after_error_response(/.*/) do |code, body, _header, message|
                puts "Warning: Could not fetch project-resource #{resource_id}: #{code} - #{message}"
                nil
              end
            
            if resource_response && resource_response['data']
              resource_data = resource_response['data']
              # Store the resource name and other details from attributes.resource
              resource_info = resource_data.dig('attributes', 'resource')
              standard_resource_id = resource_info&.dig('resource_id')
              
              # Collect standard resource IDs
              if standard_resource_id.present?
                standard_resource_id_int = standard_resource_id.to_i
                standard_resource_ids << standard_resource_id_int unless standard_resource_ids.include?(standard_resource_id_int)
              end
              
              project_resources_map[resource_id] = {
                name: resource_info&.dig('name'),
                hourly_rate: resource_info&.dig('hourly_rate'),
                hourly_cost: resource_info&.dig('hourly_cost'),
                resource_id: standard_resource_id,
                project_resource_name: resource_data.dig('attributes', 'name'),
                project_resource_extended_name: resource_data.dig('attributes', 'extended-name'),
                project_resource_description: resource_data.dig('attributes', 'description'),
                project_resource_hourly_rate: resource_data.dig('attributes', 'hourly-rate'),
                project_resource_hourly_cost: resource_data.dig('attributes', 'hourly-cost'),
                project_resource_code: resource_data.dig('attributes', 'code'),
                project_resource_active: resource_data.dig('attributes', 'active')
              }
            end
          rescue => e
            puts "Warning: Could not fetch project-resource #{resource_id}: #{e.message}"
          end
        end
        
        # Fetch standard resource information for all unique standard resource IDs
        standard_resources_map = {}
        standard_resource_ids.each do |standard_resource_id|
          begin
            standard_resource_response = get("/#{account_slug}/v1/resources/#{standard_resource_id}")
              .params(include: 'account,governances')
              .headers('Accept': 'application/vnd.api+json')
              .after_error_response(/.*/) do |code, body, _header, message|
                puts "Warning: Could not fetch standard resource #{standard_resource_id}: #{code} - #{message}"
                nil
              end
            
            if standard_resource_response && standard_resource_response['data']
              standard_resource_data = standard_resource_response['data']
              standard_resources_map[standard_resource_id] = {
                resource_id: standard_resource_id,
                resource_type: standard_resource_data['type'],
                resource_active: standard_resource_data.dig('attributes', 'active'),
                resource_name: standard_resource_data.dig('attributes', 'name'),
                resource_external_name: standard_resource_data.dig('attributes', 'external-name'),
                resource_description: standard_resource_data.dig('attributes', 'description'),
                resource_hourly_rate: standard_resource_data.dig('attributes', 'hourly-rate'),
                resource_hourly_cost: standard_resource_data.dig('attributes', 'hourly-cost')
              }
            end
          rescue => e
            puts "Warning: Could not fetch standard resource #{standard_resource_id}: #{e.message}"
          end
        end
        
        # Update project_resources_map with standard resource info
        project_resources_map.each do |project_resource_id, info|
          standard_resource_id = info[:resource_id]&.to_i
          if standard_resource_id.present? && standard_resource_id > 0 && standard_resources_map[standard_resource_id]
            project_resources_map[project_resource_id].merge!(standard_resources_map[standard_resource_id])
          end
        end

        # Add project-resource and standard resource information to each governance
        enriched_data = all_data.map do |governance|
          # Add integer conversions for hours in attributes
          if governance['attributes']
            attrs = governance['attributes']
            if attrs['fixed-hours'].present?
              attrs['fixed_hours_in_minutes'] = (attrs['fixed-hours'].to_f * 60).to_i
            end
            if attrs['hours'].present?
              attrs['hours_in_minutes'] = (attrs['hours'].to_f * 60).to_i
            end
          end
          
          # Look up the project-resource ID from our mapping
          governance_id = governance['id']
          project_resource_id = governance_to_project_resource_map[governance_id]
          
          # If we have a project-resource ID, get the info from our map
          if project_resource_id && project_resources_map[project_resource_id]
            resource_info = project_resources_map[project_resource_id]
            merged_data = {
              # Standard resource fields (from attributes.resource in project-resource)
              'resource_name' => resource_info[:name],
              'resource_hourly_rate' => resource_info[:hourly_rate],
              'resource_hourly_cost' => resource_info[:hourly_cost],
              'resource_id' => resource_info[:resource_id]&.to_i,
              # Project resource fields
              'project_resource_name' => resource_info[:project_resource_name],
              'project_resource_extended_name' => resource_info[:project_resource_extended_name],
              'project_resource_description' => resource_info[:project_resource_description],
              'project_resource_hourly_rate' => resource_info[:project_resource_hourly_rate],
              'project_resource_hourly_cost' => resource_info[:project_resource_hourly_cost],
              'project_resource_code' => resource_info[:project_resource_code],
              'project_resource_active' => resource_info[:project_resource_active],
              # Standard resource fields (from full standard resource API call)
              'standard_resource_id' => resource_info[:resource_id]&.to_i,
              'standard_resource_type' => resource_info[:resource_type],
              'standard_resource_active' => resource_info[:resource_active],
              'standard_resource_name' => resource_info[:resource_name],
              'standard_resource_external_name' => resource_info[:resource_external_name],
              'standard_resource_description' => resource_info[:resource_description],
              'standard_resource_hourly_rate' => resource_info[:resource_hourly_rate],
              'standard_resource_hourly_cost' => resource_info[:resource_hourly_cost]
            }
            
            # Add integer conversions for rates (cents)
            if resource_info[:hourly_rate].present?
              merged_data['resource_hourly_rate_in_cents'] = (resource_info[:hourly_rate].to_f * 100).to_i
            end
            if resource_info[:hourly_cost].present?
              merged_data['resource_hourly_cost_in_cents'] = (resource_info[:hourly_cost].to_f * 100).to_i
            end
            if resource_info[:project_resource_hourly_rate].present?
              merged_data['project_resource_hourly_rate_in_cents'] = (resource_info[:project_resource_hourly_rate].to_f * 100).to_i
            end
            if resource_info[:project_resource_hourly_cost].present?
              merged_data['project_resource_hourly_cost_in_cents'] = (resource_info[:project_resource_hourly_cost].to_f * 100).to_i
            end
            if resource_info[:resource_hourly_rate].present?
              merged_data['standard_resource_hourly_rate_in_cents'] = (resource_info[:resource_hourly_rate].to_f * 100).to_i
            end
            if resource_info[:resource_hourly_cost].present?
              merged_data['standard_resource_hourly_cost_in_cents'] = (resource_info[:resource_hourly_cost].to_f * 100).to_i
            end
            
            governance.merge(merged_data)
          else
            governance
          end
        end

        # Sort by position attribute
        sorted_data = enriched_data.sort_by do |governance|
          governance.dig('attributes', 'position') || 0
        end

        # Return the combined data
        {
          data: sorted_data,
          meta: {
            total_count: sorted_data.size
          }
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: "data",
            type: "array",
            of: "object",
            properties: object_definitions['project_governance'].concat([
              { name: "resource_name", type: "string", label: "Resource Name", optional: true },
              { name: "resource_hourly_rate", type: "string", label: "Resource Hourly Rate", optional: true },
              { name: "resource_hourly_cost", type: "string", label: "Resource Hourly Cost", optional: true },
              { name: "resource_hourly_rate_in_cents", type: "integer", label: "Resource Hourly Rate (in cents)", optional: true },
              { name: "resource_hourly_cost_in_cents", type: "integer", label: "Resource Hourly Cost (in cents)", optional: true },
              { name: "resource_id", type: "integer", label: "Resource ID", optional: true },
              { name: "project_resource_name", type: "string", label: "Project Resource Name", optional: true },
              { name: "project_resource_extended_name", type: "string", label: "Project Resource Extended Name", optional: true },
              { name: "project_resource_description", type: "string", label: "Project Resource Description", optional: true },
              { name: "project_resource_hourly_rate", type: "string", label: "Project Resource Hourly Rate", optional: true },
              { name: "project_resource_hourly_cost", type: "string", label: "Project Resource Hourly Cost", optional: true },
              { name: "project_resource_hourly_rate_in_cents", type: "integer", label: "Project Resource Hourly Rate (in cents)", optional: true },
              { name: "project_resource_hourly_cost_in_cents", type: "integer", label: "Project Resource Hourly Cost (in cents)", optional: true },
              { name: "project_resource_code", type: "string", label: "Project Resource Code", optional: true },
              { name: "project_resource_active", type: "boolean", label: "Project Resource Active", optional: true },
              { name: "standard_resource_id", type: "integer", label: "Standard Resource ID", optional: true },
              { name: "standard_resource_type", type: "string", label: "Standard Resource Type", optional: true },
              { name: "standard_resource_active", type: "boolean", label: "Standard Resource Active", optional: true },
              { name: "standard_resource_name", type: "string", label: "Standard Resource Name", optional: true },
              { name: "standard_resource_external_name", type: "string", label: "Standard Resource External Name", optional: true },
              { name: "standard_resource_description", type: "string", label: "Standard Resource Description", optional: true },
              { name: "standard_resource_hourly_rate", type: "string", label: "Standard Resource Hourly Rate", optional: true },
              { name: "standard_resource_hourly_cost", type: "string", label: "Standard Resource Hourly Cost", optional: true },
              { name: "standard_resource_hourly_rate_in_cents", type: "integer", label: "Standard Resource Hourly Rate (in cents)", optional: true },
              { name: "standard_resource_hourly_cost_in_cents", type: "integer", label: "Standard Resource Hourly Cost (in cents)", optional: true }
            ])
          },
          {
            name: "meta",
            type: "object",
            properties: [
              { name: "total_count", type: "integer", label: "Total Count" }
            ]
          }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        {
          "data" => [
            {
              "id" => "324113",
              "type" => "project-governances",
              "links" => {
                "allocation-methods" => "https://api.scopestack.io/zz-workato-testing-account/v1/governance-allocation-methods",
                "calculation-types" => "https://api.scopestack.io/zz-workato-testing-account/v1/governance-calculation-types",
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113"
              },
              "attributes" => {
                "active" => true,
                "description" => "Documentation",
                "rate" => "0.1",
                "fixed-hours" => "0.0",
                "calculation-type" => "percent_of_total",
                "allocation-method" => "prorate_phases_by_effort",
                "hours" => "3.8",
                "assign-effort-to-service" => false,
                "filter-type" => "all_services",
                "filter-id" => nil,
                "position" => 1,
                "project-variables" => []
              },
              "relationships" => {
                "project" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/relationships/project",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/project"
                  },
                  "data" => {
                    "type" => "projects",
                    "id" => "87343"
                  }
                }
              }
            }
          ],
          "meta" => {
            "total_count" => 1
          }
        }
      end
    },

    get_project_governance: {
      title: "Get Project Governance",
      subtitle: "Get a specific project governance by ID",
      description: "Get a specific <span class='provider'>project governance</span> in <span class='provider'>ScopeStack</span>",
      help: "Retrieves a specific project governance using its ID. Optionally includes related data.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "project_governance_id",
            label: "Project Governance ID",
            type: "string",
            control_type: "text",
            optional: false,
            hint: "The ID of the project governance to retrieve."
          },
          {
            name: "includes",
            label: "Include Related Data",
            type: "object",
            properties: [
              {
                name: "include_resource",
                label: "Resource",
                control_type: "checkbox",
                type: "boolean",
                optional: true,
                sticky: true,
                hint: "Include resource information"
              },
              {
                name: "include_project_phase",
                label: "Project Phase",
                control_type: "checkbox",
                type: "boolean",
                optional: true,
                sticky: true,
                hint: "Include project phase information"
              },
              {
                name: "include_project_resource",
                label: "Project Resource",
                control_type: "checkbox",
                type: "boolean",
                optional: true,
                sticky: true,
                hint: "Include project resource information"
              },
              {
                name: "include_project",
                label: "Project",
                control_type: "checkbox",
                type: "boolean",
                optional: true,
                sticky: true,
                hint: "Include project information"
              },
              {
                name: "include_service_category",
                label: "Service Category",
                control_type: "checkbox",
                type: "boolean",
                optional: true,
                sticky: true,
                hint: "Include service category information"
              }
            ]
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Validate that project_governance_id is provided
        if input['project_governance_id'].blank?
          error("Project Governance ID must be provided to retrieve the governance.")
        end

        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Build includes array from checkboxes
        includes = []
        includes << 'resource' if input.dig('includes', 'include_resource')
        includes << 'project-phase' if input.dig('includes', 'include_project_phase')
        includes << 'project-resource' if input.dig('includes', 'include_project_resource')
        includes << 'project' if input.dig('includes', 'include_project')
        includes << 'service-category' if input.dig('includes', 'include_service_category')

        # Build params
        params = {}
        params["include"] = includes.join(',') if includes.any?

        # Get the project governance by ID
        response = get("/#{account_slug}/v1/project-governances/#{input['project_governance_id']}")
          .params(params)
          .headers('Accept': 'application/vnd.api+json')
          .after_error_response(/.*/) do |code, body, _header, message|
            case code
            when 404
              error("Project governance with ID '#{input['project_governance_id']}' not found")
            when 401, 403
              error("Authentication failed or insufficient permissions: #{message}")
            else
              error("Failed to fetch project governance (#{code}): #{message}: #{body}")
            end
          end

        # Add integer conversions for hours
        if response['data'] && response['data']['attributes']
          attrs = response['data']['attributes']
          if attrs['fixed-hours'].present?
            attrs['fixed_hours_in_minutes'] = (attrs['fixed-hours'].to_f * 60).to_i
          end
          if attrs['hours'].present?
            attrs['hours_in_minutes'] = (attrs['hours'].to_f * 60).to_i
          end
        end

        governance = response['data']
        
        # Always fetch project-resource and standard resource information
        governance_id = governance['id']
        project_resource_id = nil
        
        # Try to get project-resource ID from relationships data first
        project_resource_data = governance.dig('relationships', 'project-resource', 'data')
        
        if project_resource_data && project_resource_data['id']
          project_resource_id = project_resource_data['id']
        else
          # If not in data, try to fetch from the related link
          project_resource_link = governance.dig('relationships', 'project-resource', 'links', 'related') || 
                                 governance.dig('relationships', 'project-resource', 'links', 'self')
          if project_resource_link
            begin
              # Extract just the path portion from the URL
              uri = URI.parse(project_resource_link)
              path = uri.path
              
              # Fetch the project-resource from the related endpoint
              pr_response = get(path)
                .headers('Accept': 'application/vnd.api+json')
                .after_error_response(/.*/) do |code, body, _header, message|
                  puts "Warning: Could not fetch project-resource from link for governance #{governance_id}: #{code} - #{message}"
                  nil
                end
              
              if pr_response && pr_response['data']
                project_resource_id = pr_response['data']['id']
              end
            rescue => e
              puts "Warning: Could not fetch project-resource from link for governance #{governance_id}: #{e.message}"
            end
          end
        end
        
        # If we have a project-resource ID, fetch and enrich with resource data
        if project_resource_id.present?
          begin
            resource_response = get("/#{account_slug}/v1/project-resources/#{project_resource_id}")
              .after_error_response(/.*/) do |code, body, _header, message|
                puts "Warning: Could not fetch project-resource #{project_resource_id}: #{code} - #{message}"
                nil
              end
            
            if resource_response && resource_response['data']
              resource_data = resource_response['data']
              resource_info = resource_data.dig('attributes', 'resource')
              standard_resource_id = resource_info&.dig('resource_id')
              
              # Build resource info map
              project_resource_info = {
                name: resource_info&.dig('name'),
                hourly_rate: resource_info&.dig('hourly_rate'),
                hourly_cost: resource_info&.dig('hourly_cost'),
                resource_id: standard_resource_id,
                project_resource_name: resource_data.dig('attributes', 'name'),
                project_resource_extended_name: resource_data.dig('attributes', 'extended-name'),
                project_resource_description: resource_data.dig('attributes', 'description'),
                project_resource_hourly_rate: resource_data.dig('attributes', 'hourly-rate'),
                project_resource_hourly_cost: resource_data.dig('attributes', 'hourly-cost'),
                project_resource_code: resource_data.dig('attributes', 'code'),
                project_resource_active: resource_data.dig('attributes', 'active')
              }
              
              # Fetch standard resource if we have the ID
              if standard_resource_id.present?
                standard_resource_id_int = standard_resource_id.to_i
                begin
                  standard_resource_response = get("/#{account_slug}/v1/resources/#{standard_resource_id_int}")
                    .params(include: 'account,governances')
                    .headers('Accept': 'application/vnd.api+json')
                    .after_error_response(/.*/) do |code, body, _header, message|
                      puts "Warning: Could not fetch standard resource #{standard_resource_id_int}: #{code} - #{message}"
                      nil
                    end
                  
                  if standard_resource_response && standard_resource_response['data']
                    standard_resource_data = standard_resource_response['data']
                    project_resource_info.merge!({
                      resource_type: standard_resource_data['type'],
                      resource_active: standard_resource_data.dig('attributes', 'active'),
                      resource_name: standard_resource_data.dig('attributes', 'name'),
                      resource_external_name: standard_resource_data.dig('attributes', 'external-name'),
                      resource_description: standard_resource_data.dig('attributes', 'description'),
                      resource_hourly_rate: standard_resource_data.dig('attributes', 'hourly-rate'),
                      resource_hourly_cost: standard_resource_data.dig('attributes', 'hourly-cost')
                    })
                  end
                rescue => e
                  puts "Warning: Could not fetch standard resource #{standard_resource_id_int}: #{e.message}"
                end
              end
              
              # Merge resource data into governance
              merged_data = {
                # Standard resource fields (from attributes.resource in project-resource)
                'resource_name' => project_resource_info[:name],
                'resource_hourly_rate' => project_resource_info[:hourly_rate],
                'resource_hourly_cost' => project_resource_info[:hourly_cost],
                'resource_id' => project_resource_info[:resource_id]&.to_i,
                # Project resource fields
                'project_resource_name' => project_resource_info[:project_resource_name],
                'project_resource_extended_name' => project_resource_info[:project_resource_extended_name],
                'project_resource_description' => project_resource_info[:project_resource_description],
                'project_resource_hourly_rate' => project_resource_info[:project_resource_hourly_rate],
                'project_resource_hourly_cost' => project_resource_info[:project_resource_hourly_cost],
                'project_resource_code' => project_resource_info[:project_resource_code],
                'project_resource_active' => project_resource_info[:project_resource_active],
                # Standard resource fields (from full standard resource API call)
                'standard_resource_id' => project_resource_info[:resource_id]&.to_i,
                'standard_resource_type' => project_resource_info[:resource_type],
                'standard_resource_active' => project_resource_info[:resource_active],
                'standard_resource_name' => project_resource_info[:resource_name],
                'standard_resource_external_name' => project_resource_info[:resource_external_name],
                'standard_resource_description' => project_resource_info[:resource_description],
                'standard_resource_hourly_rate' => project_resource_info[:resource_hourly_rate],
                'standard_resource_hourly_cost' => project_resource_info[:resource_hourly_cost]
              }
              
              # Add integer conversions for rates (cents)
              if project_resource_info[:hourly_rate].present?
                merged_data['resource_hourly_rate_in_cents'] = (project_resource_info[:hourly_rate].to_f * 100).to_i
              end
              if project_resource_info[:hourly_cost].present?
                merged_data['resource_hourly_cost_in_cents'] = (project_resource_info[:hourly_cost].to_f * 100).to_i
              end
              if project_resource_info[:project_resource_hourly_rate].present?
                merged_data['project_resource_hourly_rate_in_cents'] = (project_resource_info[:project_resource_hourly_rate].to_f * 100).to_i
              end
              if project_resource_info[:project_resource_hourly_cost].present?
                merged_data['project_resource_hourly_cost_in_cents'] = (project_resource_info[:project_resource_hourly_cost].to_f * 100).to_i
              end
              if project_resource_info[:resource_hourly_rate].present?
                merged_data['standard_resource_hourly_rate_in_cents'] = (project_resource_info[:resource_hourly_rate].to_f * 100).to_i
              end
              if project_resource_info[:resource_hourly_cost].present?
                merged_data['standard_resource_hourly_cost_in_cents'] = (project_resource_info[:resource_hourly_cost].to_f * 100).to_i
              end
              
              governance = governance.merge(merged_data)
            end
          rescue => e
            puts "Warning: Could not fetch project-resource #{project_resource_id}: #{e.message}"
          end
        end

        governance
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['project_governance'].concat([
          { name: "resource_name", type: "string", label: "Resource Name", optional: true },
          { name: "resource_hourly_rate", type: "string", label: "Resource Hourly Rate", optional: true },
          { name: "resource_hourly_cost", type: "string", label: "Resource Hourly Cost", optional: true },
          { name: "resource_hourly_rate_in_cents", type: "integer", label: "Resource Hourly Rate (in cents)", optional: true },
          { name: "resource_hourly_cost_in_cents", type: "integer", label: "Resource Hourly Cost (in cents)", optional: true },
          { name: "resource_id", type: "integer", label: "Resource ID", optional: true },
          { name: "project_resource_name", type: "string", label: "Project Resource Name", optional: true },
          { name: "project_resource_extended_name", type: "string", label: "Project Resource Extended Name", optional: true },
          { name: "project_resource_description", type: "string", label: "Project Resource Description", optional: true },
          { name: "project_resource_hourly_rate", type: "string", label: "Project Resource Hourly Rate", optional: true },
          { name: "project_resource_hourly_cost", type: "string", label: "Project Resource Hourly Cost", optional: true },
          { name: "project_resource_hourly_rate_in_cents", type: "integer", label: "Project Resource Hourly Rate (in cents)", optional: true },
          { name: "project_resource_hourly_cost_in_cents", type: "integer", label: "Project Resource Hourly Cost (in cents)", optional: true },
          { name: "project_resource_code", type: "string", label: "Project Resource Code", optional: true },
          { name: "project_resource_active", type: "boolean", label: "Project Resource Active", optional: true },
          { name: "standard_resource_id", type: "integer", label: "Standard Resource ID", optional: true },
          { name: "standard_resource_type", type: "string", label: "Standard Resource Type", optional: true },
          { name: "standard_resource_active", type: "boolean", label: "Standard Resource Active", optional: true },
          { name: "standard_resource_name", type: "string", label: "Standard Resource Name", optional: true },
          { name: "standard_resource_external_name", type: "string", label: "Standard Resource External Name", optional: true },
          { name: "standard_resource_description", type: "string", label: "Standard Resource Description", optional: true },
          { name: "standard_resource_hourly_rate", type: "string", label: "Standard Resource Hourly Rate", optional: true },
          { name: "standard_resource_hourly_cost", type: "string", label: "Standard Resource Hourly Cost", optional: true },
          { name: "standard_resource_hourly_rate_in_cents", type: "integer", label: "Standard Resource Hourly Rate (in cents)", optional: true },
          { name: "standard_resource_hourly_cost_in_cents", type: "integer", label: "Standard Resource Hourly Cost (in cents)", optional: true }
        ])
      end,

      sample_output: lambda do |_connection, _input|
        {
          "id" => "324113",
          "type" => "project-governances",
          "links" => {
            "allocation-methods" => "https://api.scopestack.io/zz-workato-testing-account/v1/governance-allocation-methods",
            "calculation-types" => "https://api.scopestack.io/zz-workato-testing-account/v1/governance-calculation-types",
            "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113"
          },
          "attributes" => {
            "active" => true,
            "description" => "Documentation",
            "rate" => "0.1",
            "fixed-hours" => "0.0",
            "calculation-type" => "percent_of_total",
            "allocation-method" => "prorate_phases_by_effort",
            "hours" => "3.8",
            "rate_in_cents" => 10,
            "fixed_hours_in_minutes" => 0,
            "hours_in_minutes" => 228,
            "assign-effort-to-service" => false,
            "filter-type" => "all_services",
            "filter-id" => nil,
            "position" => 1,
            "project-variables" => [
              {
                "name" => "gov_character",
                "label" => "Governance Item Character",
                "variable_type" => "text",
                "minimum" => nil,
                "maximum" => nil,
                "required" => false,
                "select_options" => [],
                "position" => 14,
                "context" => "governance",
                "uuid" => "efa55c9a-772b-4210-85a1-7251bfc2bb39",
                "value" => nil
              }
            ]
          },
          "relationships" => {
            "project" => {
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/relationships/project",
                "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/project"
              },
              "data" => {
                "type" => "projects",
                "id" => "87343"
              }
            },
            "project-phase" => {
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/relationships/project-phase",
                "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/project-phase"
              },
              "data" => nil
            },
            "governance" => {
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/relationships/governance",
                "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/governance"
              }
            },
            "project-resource" => {
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/relationships/project-resource",
                "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/project-resource"
              },
              "data" => {
                "type" => "project-resources",
                "id" => "275828"
              }
            },
            "resource" => {
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/relationships/resource",
                "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/resource"
              },
              "data" => {
                "type" => "resources",
                "id" => "15866"
              }
            },
            "resource-rate" => {
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/relationships/resource-rate",
                "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/resource-rate"
              }
            },
            "service-category" => {
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/relationships/service-category",
                "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-governances/324113/service-category"
              },
              "data" => nil
            }
          }
        }
      end
    },

    list_resources: {
      title: "List Resources",
      subtitle: "Get all resources in the account",
      description: "List <span class='provider'>resources</span> in <span class='provider'>ScopeStack</span>",
      help: "Retrieves all resources in the account. Optionally filter by active status. This action automatically handles pagination to return all resources.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "active",
            label: "Active Only",
            type: "boolean",
            control_type: "checkbox",
            optional: true,
            hint: "If checked, only return active resources. If unchecked or not specified, returns all resources.",
            sticky: true
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        # Set up filters and pagination
        filters = {
          "include" => "account,governances",
          "page[size]" => 250
        }

        # Add active filter if specified
        if input['active'] == true
          filters["filter[active]"] = "true"
        end

        all_data = []
        current_page = 1
        has_more_pages = true

        while has_more_pages
          filters["page[number]"] = current_page
          
          response = get("/#{account_slug}/v1/resources")
            .params(filters)
            .headers('Accept': 'application/vnd.api+json')
            .after_error_response(/.*/) do |code, body, _header, message|
              case code
              when 404
                error("Resources endpoint not found")
              when 401, 403
                error("Authentication failed or insufficient permissions: #{message}")
              else
                error("Failed to fetch resources (#{code}): #{message}: #{body}")
              end
            end
          
          # Add the current page's data to our collection
          all_data.concat(response['data'] || [])

          # Check if there are more pages
          total_pages = response.dig('meta', 'page-count') || 1
          has_more_pages = current_page < total_pages
          current_page += 1
        end

        # Return the combined data
        {
          data: all_data,
          meta: {
            "record-count": all_data.size,
            "page-count": (all_data.size.to_f / 250.0).ceil
          }
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: "data",
            type: "array",
            of: "object",
            properties: object_definitions['resource']
          },
          {
            name: "meta",
            type: "object",
            properties: [
              { name: "record-count", type: "integer", label: "Record Count" },
              { name: "page-count", type: "integer", label: "Page Count" }
            ]
          }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        {
          "data" => [
            {
              "id" => "15865",
              "type" => "resources",
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/resources/15865"
              },
              "attributes" => {
                "active" => true,
                "name" => "Consultant",
                "external-name" => "",
                "description" => nil,
                "hourly-rate" => "200.0",
                "hourly-cost" => "130.0"
              },
              "relationships" => {
                "account" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/resources/15865/relationships/account",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/resources/15865/account"
                  },
                  "data" => {
                    "type" => "accounts",
                    "id" => "zz-workato-testing-account"
                  }
                },
                "governances" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/resources/15865/relationships/governances",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/resources/15865/governances"
                  },
                  "data" => []
                }
              }
            }
          ],
          "meta" => {
            "record-count" => 1,
            "page-count" => 1
          }
        }
      end
    },

    get_resource: {
      title: "Get Resource",
      subtitle: "Get a specific resource by ID",
      description: "Get a specific <span class='provider'>resource</span> in <span class='provider'>ScopeStack</span>",
      help: "Retrieves a specific resource using its Resource ID.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "resource_id",
            label: "Resource ID",
            type: "string",
            control_type: "text",
            optional: false,
            hint: "The ID of the resource to retrieve."
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Validate that resource_id is provided
        if input['resource_id'].blank?
          error("Resource ID must be provided to retrieve the resource.")
        end

        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Get the resource by ID
        response = get("/#{account_slug}/v1/resources/#{input['resource_id']}")
          .params(include: 'account,governances')
          .headers('Accept': 'application/vnd.api+json')
          .after_error_response(/.*/) do |code, body, _header, message|
            case code
            when 404
              error("Resource with ID '#{input['resource_id']}' not found")
            when 401, 403
              error("Authentication failed or insufficient permissions: #{message}")
            else
              error("Failed to fetch resource (#{code}): #{message}: #{body}")
            end
          end

        response['data']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['resource']
      end,

      sample_output: lambda do |_connection, _input|
        {
          "id" => "15865",
          "type" => "resources",
          "links" => {
            "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/resources/15865"
          },
          "attributes" => {
            "active" => true,
            "name" => "Consultant",
            "external-name" => "",
            "description" => nil,
            "hourly-rate" => "200.0",
            "hourly-cost" => "130.0"
          },
          "relationships" => {
            "account" => {
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/resources/15865/relationships/account",
                "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/resources/15865/account"
              },
              "data" => {
                "type" => "accounts",
                "id" => "zz-workato-testing-account"
              }
            },
            "governances" => {
              "links" => {
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/resources/15865/relationships/governances",
                "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/resources/15865/governances"
              },
              "data" => []
            }
          }
        }
      end
    },

    list_standard_resources_for_project: {
      title: "List Standard Resources for Project",
      subtitle: "Get standard resource information for all project resources",
      description: "List <span class='provider'>standard resource information</span> for all <span class='provider'>project resources</span> in <span class='provider'>ScopeStack</span>",
      help: "Retrieves all project resources for a specific project, then fetches the corresponding standard resource information for each. Returns a consolidated array with both project resource and standard resource details, clearly labeled by source.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "project_id",
            label: "Project ID",
            type: "integer",
            optional: false,
            hint: "Enter the ID of the project to get standard resource information for",
            sticky: true
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        # Validate project_id is a number
        project_id = input['project_id'].to_s.strip
        unless project_id.match?(/^\d+$/)
          error("Project ID must be a valid number")
        end

        # Fetch all project resources (resource_id is available in attributes.resource.resource_id)
        filters = {
          "page[size]" => 100
        }

        all_project_resources = []
        current_page = 1
        has_more_pages = true

        while has_more_pages
          filters["page[number]"] = current_page
          
          response = get("/#{account_slug}/v1/projects/#{project_id}/project-resources")
            .params(filters)
            .headers('Accept': 'application/vnd.api+json')
            .after_error_response(/.*/) do |code, body, _header, message|
              case code
              when 404
                error("Project not found with ID: #{project_id}")
              when 401, 403
                error("Authentication failed or insufficient permissions: #{message}")
              else
                error("Failed to fetch project resources (#{code}): #{message}: #{body}")
              end
            end
          
          all_project_resources.concat(response['data'] || [])

          total_pages = response.dig('meta', 'page-count') || 1
          has_more_pages = current_page < total_pages
          current_page += 1
        end

        # Extract unique resource IDs from both sources
        resource_ids = []
        project_resource_map = {}

        all_project_resources.each do |pr|
          pr_id = pr['id']
          resource_id = nil
          
          # Try to get resource_id from attributes.resource.resource_id
          if pr.dig('attributes', 'resource', 'resource_id').present?
            resource_id = pr.dig('attributes', 'resource', 'resource_id')&.to_i
          # Try to get resource_id from relationships.resource.data.id
          elsif pr.dig('relationships', 'resource', 'data', 'id').present?
            resource_id = pr.dig('relationships', 'resource', 'data', 'id')&.to_i
          end

          if resource_id.present?
            resource_ids << resource_id unless resource_ids.include?(resource_id)
            project_resource_map[resource_id] ||= []
            project_resource_map[resource_id] << pr
          else
            # If no resource_id found, still include the project resource with null standard resource
            project_resource_map[nil] ||= []
            project_resource_map[nil] << pr
          end
        end

        # Fetch standard resources for all unique resource IDs
        standard_resources = {}
        resource_ids.each do |resource_id|
          begin
            response = get("/#{account_slug}/v1/resources/#{resource_id}")
              .params(include: 'account,governances')
              .headers('Accept': 'application/vnd.api+json')
              .after_error_response(/.*/) do |code, body, _header, message|
                # If resource not found, set to nil (will be handled below)
                if code == 404
                  standard_resources[resource_id] = nil
                  next
                else
                  error("Failed to fetch standard resource #{resource_id} (#{code}): #{message}: #{body}")
                end
              end
            
            standard_resources[resource_id] = response['data'] if response && response['data']
          rescue => e
            # If any error occurs, set to nil
            standard_resources[resource_id] = nil
          end
        end

        # Build consolidated array
        consolidated_results = []

        all_project_resources.each do |pr|
          pr_id = pr['id']
          resource_id = nil
          
          # Try to get resource_id from attributes.resource.resource_id
          if pr.dig('attributes', 'resource', 'resource_id').present?
            resource_id = pr.dig('attributes', 'resource', 'resource_id')&.to_i
          # Try to get resource_id from relationships.resource.data.id
          elsif pr.dig('relationships', 'resource', 'data', 'id').present?
            resource_id = pr.dig('relationships', 'resource', 'data', 'id')&.to_i
          end

          standard_resource = resource_id.present? ? standard_resources[resource_id] : nil

          # Build consolidated object
          consolidated = {
            # Project Resource fields (prefixed with project_resource_)
            "project_resource_id" => pr_id,
            "project_resource_type" => pr['type'],
            "project_resource_active" => pr.dig('attributes', 'active'),
            "project_resource_name" => pr.dig('attributes', 'name'),
            "project_resource_external_name" => pr.dig('attributes', 'external-name'),
            "project_resource_extended_name" => pr.dig('attributes', 'extended-name'),
            "project_resource_description" => pr.dig('attributes', 'description'),
            "project_resource_total_hours" => pr.dig('attributes', 'total-hours'),
            "project_resource_hourly_rate" => pr.dig('attributes', 'hourly-rate'),
            "project_resource_hourly_cost" => pr.dig('attributes', 'hourly-cost'),
            "project_resource_expense_rate" => pr.dig('attributes', 'expense-rate'),
            "project_resource_code" => pr.dig('attributes', 'code'),
            # Resource ID from both sources
            "resource_id_from_attributes" => pr.dig('attributes', 'resource', 'resource_id')&.to_i,
            "resource_id_from_relationships" => pr.dig('relationships', 'resource', 'data', 'id')&.to_i,
            # Standard Resource fields (prefixed with resource_)
            "resource_id" => resource_id,
            "resource_type" => standard_resource ? standard_resource['type'] : nil,
            "resource_active" => standard_resource ? standard_resource.dig('attributes', 'active') : nil,
            "resource_name" => standard_resource ? standard_resource.dig('attributes', 'name') : nil,
            "resource_external_name" => standard_resource ? standard_resource.dig('attributes', 'external-name') : nil,
            "resource_description" => standard_resource ? standard_resource.dig('attributes', 'description') : nil,
            "resource_hourly_rate" => standard_resource ? standard_resource.dig('attributes', 'hourly-rate') : nil,
            "resource_hourly_cost" => standard_resource ? standard_resource.dig('attributes', 'hourly-cost') : nil
          }
          
          # Add integer conversions for rates (cents) and hours (minutes)
          total_hours = pr.dig('attributes', 'total-hours')
          hourly_rate = pr.dig('attributes', 'hourly-rate')
          hourly_cost = pr.dig('attributes', 'hourly-cost')
          expense_rate = pr.dig('attributes', 'expense-rate')
          resource_hourly_rate = standard_resource ? standard_resource.dig('attributes', 'hourly-rate') : nil
          resource_hourly_cost = standard_resource ? standard_resource.dig('attributes', 'hourly-cost') : nil
          
          if total_hours.present?
            consolidated["project_resource_total_hours_in_minutes"] = (total_hours.to_f * 60).to_i
          end
          if hourly_rate.present?
            consolidated["project_resource_hourly_rate_in_cents"] = (hourly_rate.to_f * 100).to_i
          end
          if hourly_cost.present?
            consolidated["project_resource_hourly_cost_in_cents"] = (hourly_cost.to_f * 100).to_i
          end
          if expense_rate.present?
            consolidated["project_resource_expense_rate_in_cents"] = (expense_rate.to_f * 100).to_i
          end
          if resource_hourly_rate.present?
            consolidated["resource_hourly_rate_in_cents"] = (resource_hourly_rate.to_f * 100).to_i
          end
          if resource_hourly_cost.present?
            consolidated["resource_hourly_cost_in_cents"] = (resource_hourly_cost.to_f * 100).to_i
          end
          
          consolidated

          consolidated_results << consolidated
        end

        {
          data: consolidated_results,
          meta: {
            total_count: consolidated_results.size,
            project_resources_count: all_project_resources.size,
            standard_resources_found: standard_resources.values.count { |sr| sr != nil },
            standard_resources_not_found: standard_resources.values.count { |sr| sr == nil }
          }
        }
      end,

      output_fields: lambda do |_object_definitions|
        [
          {
            name: "data",
            type: "array",
            of: "object",
            properties: [
              # Project Resource fields
              { name: "project_resource_id", type: "integer", label: "Project Resource ID" },
              { name: "project_resource_type", type: "string", label: "Project Resource Type" },
              { name: "project_resource_active", type: "boolean", label: "Project Resource Active" },
              { name: "project_resource_name", type: "string", label: "Project Resource Name" },
              { name: "project_resource_external_name", type: "string", label: "Project Resource External Name", optional: true },
              { name: "project_resource_extended_name", type: "string", label: "Project Resource Extended Name" },
              { name: "project_resource_description", type: "string", label: "Project Resource Description", optional: true },
              { name: "project_resource_total_hours", type: "string", label: "Project Resource Total Hours" },
              { name: "project_resource_hourly_rate", type: "string", label: "Project Resource Hourly Rate" },
              { name: "project_resource_hourly_cost", type: "string", label: "Project Resource Hourly Cost" },
              { name: "project_resource_expense_rate", type: "string", label: "Project Resource Expense Rate" },
              { name: "project_resource_total_hours_in_minutes", type: "integer", label: "Project Resource Total Hours (in minutes)", optional: true },
              { name: "project_resource_hourly_rate_in_cents", type: "integer", label: "Project Resource Hourly Rate (in cents)", optional: true },
              { name: "project_resource_hourly_cost_in_cents", type: "integer", label: "Project Resource Hourly Cost (in cents)", optional: true },
              { name: "project_resource_expense_rate_in_cents", type: "integer", label: "Project Resource Expense Rate (in cents)", optional: true },
              { name: "project_resource_code", type: "string", label: "Project Resource Code", optional: true },
              # Resource ID sources
              { name: "resource_id_from_attributes", type: "string", label: "Resource ID (from attributes)", optional: true },
              { name: "resource_id_from_relationships", type: "string", label: "Resource ID (from relationships)", optional: true },
              # Standard Resource fields
              { name: "resource_id", type: "integer", label: "Standard Resource ID", optional: true },
              { name: "resource_type", type: "string", label: "Standard Resource Type", optional: true },
              { name: "resource_active", type: "boolean", label: "Standard Resource Active", optional: true },
              { name: "resource_name", type: "string", label: "Standard Resource Name", optional: true },
              { name: "resource_external_name", type: "string", label: "Standard Resource External Name", optional: true },
              { name: "resource_description", type: "string", label: "Standard Resource Description", optional: true },
              { name: "resource_hourly_rate", type: "string", label: "Standard Resource Hourly Rate", optional: true },
              { name: "resource_hourly_cost", type: "string", label: "Standard Resource Hourly Cost", optional: true },
              { name: "resource_hourly_rate_in_cents", type: "integer", label: "Standard Resource Hourly Rate (in cents)", optional: true },
              { name: "resource_hourly_cost_in_cents", type: "integer", label: "Standard Resource Hourly Cost (in cents)", optional: true }
            ]
          },
          {
            name: "meta",
            type: "object",
            properties: [
              { name: "total_count", type: "integer", label: "Total Count" },
              { name: "project_resources_count", type: "integer", label: "Project Resources Count" },
              { name: "standard_resources_found", type: "integer", label: "Standard Resources Found" },
              { name: "standard_resources_not_found", type: "integer", label: "Standard Resources Not Found" }
            ]
          }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        {
          "data" => [
            {
              "project_resource_id" => "275828",
              "project_resource_type" => "project-resources",
              "project_resource_active" => true,
              "project_resource_name" => "Engineer",
              "project_resource_external_name" => nil,
              "project_resource_extended_name" => "Engineer",
              "project_resource_description" => nil,
              "project_resource_total_hours" => "23.0",
              "project_resource_hourly_rate" => "150.0",
              "project_resource_hourly_cost" => "100.0",
              "project_resource_expense_rate" => "100.0",
              "project_resource_code" => nil,
              "resource_id_from_attributes" => "15866",
              "resource_id_from_relationships" => "15866",
              "resource_id" => "15866",
              "resource_type" => "resources",
              "resource_active" => true,
              "resource_name" => "Engineer",
              "resource_external_name" => nil,
              "resource_description" => nil,
              "resource_hourly_rate" => "150.0",
              "resource_hourly_cost" => "100.0"
            }
          ],
          "meta" => {
            "total_count" => 1,
            "project_resources_count" => 1,
            "standard_resources_found" => 1,
            "standard_resources_not_found" => 0
          }
        }
      end
    },

    list_project_services: {
      title: "List Project Services",
      subtitle: "Get all services for a specific project",
      description: "List <span class='provider'>project services</span> in <span class='provider'>ScopeStack</span>",
      help: "Retrieves all services for a specific project with optional filtering by service type and phase ID(s), and optional includes for related data. Services are automatically sorted by phase sequence and position. Project resource and standard resource information is always included in the output. Use the Filter by Phase ID(s) option to return only services from specific phases (client-side filtering). Use the Include Related Data options to fetch related objects like project-location, lob, and project-subservices via API includes (more efficient than separate calls).",

      input_fields: lambda do |connection, input|
        [
          {
            name: "project_id",
            label: "Project ID",
            type: "string",
            control_type: "number",
            optional: false,
            hint: "Enter the ID of the project to get services for",
            sticky: true
          },
          {
            name: "service_type",
            label: "Service Type",
            type: "string",
            control_type: "select",
            pick_list: [
              ["Professional Services", "professional_services"],
              ["Managed Services", "managed_services"],
              ["Both", "both"]
            ],
            default: "professional_services",
            optional: false,
            hint: "Select the type of services to retrieve. 'Both' will return all services regardless of type."
          },
          {
            name: "output_format",
            label: "Output Format",
            type: "string",
            control_type: "select",
            pick_list: [
              ["Flat Array", "flat"],
              ["Grouped by Phase", "grouped"]
            ],
            default: "flat",
            optional: false,
            hint: "Choose how to organize the output. 'Flat Array' returns all services in a single sorted list. 'Grouped by Phase' organizes services under each phase."
          },
          {
            name: "sort_order",
            label: "Sort Order",
            type: "string",
            control_type: "select",
            pick_list: [
              ["First to Last (1, 2, 3...)", "first_to_last"],
              ["Last to First (...3, 2, 1)", "last_to_first"]
            ],
            default: "first_to_last",
            optional: false,
            hint: "Choose the order to sort results by position. 'First to Last' shows position 1 first, 'Last to First' shows the highest position first."
          },
          {
            name: "phase_ids",
            label: "Filter by Phase ID(s)",
            type: "string",
            control_type: "text",
            optional: true,
            sticky: true,
            hint: "Enter one or more project phase IDs to filter services. Separate multiple IDs with commas (e.g., '602417,602418'). Leave empty to return services from all phases."
          },
          {
            name: "includes",
            label: "Include Related Data",
            type: "object",
            properties: [
              {
                name: 'include_project_location',
                label: 'Project Location',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project location information'
              },
              {
                name: 'include_lob',
                label: 'LOB',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include line of business information'
              },
              {
                name: 'include_project_phase',
                label: 'Project Phase',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                default: true,
                hint: 'Include project phase information'
              },
              {
                name: 'include_project_subservices',
                label: 'Project Subservices',
                control_type: 'checkbox',
                type: 'boolean',
                optional: true,
                sticky: true,
                hint: 'Include project subservices information'
              }
            ]
          }
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]
        
        # Validate project_id is a number
        project_id = input['project_id'].to_s.strip
        unless project_id.match?(/^\d+$/)
          error("Project ID must be a valid number")
        end

        # Validate phase_ids format if provided
        if input['phase_ids'].present?
          phase_ids_input = input['phase_ids'].to_s.strip
          phase_ids_list = phase_ids_input.split(',').map(&:strip).reject(&:empty?)
          
          phase_ids_list.each do |phase_id|
            unless phase_id.match?(/^\d+$/)
              error("Phase IDs must be valid numbers. Invalid value: #{phase_id}")
            end
          end
        end

        # Set up filters
        filters = {
          "filter[project]" => project_id,
          "page[size]" => 100
        }

        # Build includes array from checkboxes
        includes = []
        includes << 'project-location' if input.dig('includes', 'include_project_location')
        includes << 'lob' if input.dig('includes', 'include_lob')
        
        # Project phase is defaulted to true, but check if it's explicitly set
        include_project_phase = input.dig('includes', 'include_project_phase')
        if include_project_phase.nil? || include_project_phase
          includes << 'project-phase'
        end
        
        # Handle project-subservices (resource information is always fetched separately)
        if input.dig('includes', 'include_project_subservices')
          includes << 'project-subservices'
        end

        # Add includes to filters (always include project-phase for sorting logic if no other includes selected)
        if includes.any?
          filters["include"] = includes.join(',')
        else
          # Default to project-phase for backward compatibility with sorting logic
          filters["include"] = "project-phase"
        end

        # Add service type filter if not "both"
        if input['service_type'] != "both"
          filters["filter[service-type]"] = input['service_type']
        end

        # Get all project phases for sorting
        phases_map = {}
        begin
          # Call the project phases API directly
          phases_response = get("/#{account_slug}/v1/project-phases")
            .params({
              "filter[active]" => "true",
              "filter[project]" => project_id,
              "page[size]" => 100
            })
            .after_error_response(/.*/) do |code, body, _header, message|
              puts "Warning: Could not fetch phases for sorting: #{code} - #{message}: #{body}"
              # Don't error here, just continue without phase sorting
            end
          
          if phases_response && phases_response['data']
            phases_response['data'].each do |phase|
              phases_map[phase['id']] = {
                name: phase['attributes']['name'],
                position: phase['attributes']['position']
              }
            end
          end
        rescue => e
          puts "Warning: Could not fetch phases for sorting: #{e.message}"
        end

        # Fetch all services with pagination
        all_data = []
        current_page = 1
        has_more_pages = true

        while has_more_pages
          filters["page[number]"] = current_page
          
          response = get("/#{account_slug}/v1/project-services")
            .params(filters)
            .after_error_response(/.*/) do |code, body, _header, message|
              case code
              when 404
                error("Project not found with ID: #{project_id}")
              when 401, 403
                error("Authentication failed or insufficient permissions: #{message}")
              else
                error("Failed to fetch project services (#{code}): #{message}: #{body}")
              end
            end
          
          # Add the current page's data to our collection
          all_data.concat(response['data'] || [])

          # Check if there are more pages
          total_pages = response.dig('meta', 'page-count') || 1
          has_more_pages = current_page < total_pages
          current_page += 1
        end

        # Filter by phase ID(s) if specified
        if input['phase_ids'].present?
          phase_ids_filter = input['phase_ids'].to_s.strip.split(',').map(&:strip).reject(&:empty?)
          
          if phase_ids_filter.any?
            all_data = all_data.select do |service|
              phase_data = service.dig('relationships', 'project-phase', 'data')
              service_phase_id = phase_data&.dig('id')
              phase_ids_filter.include?(service_phase_id.to_s)
            end
          end
        end

        # Always fetch project-resource and standard resource information
        project_resources_map = {}
        service_to_project_resource_map = {} # Map service_id -> project_resource_id
        # Collect all unique project-resource IDs from services
        project_resource_ids = []
        all_data.each do |service|
          service_id = service['id']
          # Try to get project-resource ID from relationships data first
          project_resource_data = service.dig('relationships', 'project-resource', 'data')
          project_resource_id = nil
          
          if project_resource_data && project_resource_data['id']
            project_resource_id = project_resource_data['id']
          else
            # If not in data, try to fetch from the related link
            project_resource_link = service.dig('relationships', 'project-resource', 'links', 'related') || 
                                   service.dig('relationships', 'project-resource', 'links', 'self')
            if project_resource_link && service_id
              begin
                # Extract just the path portion from the URL
                uri = URI.parse(project_resource_link)
                path = uri.path
                
                # Fetch the project-resource from the related endpoint
                pr_response = get(path)
                  .headers('Accept': 'application/vnd.api+json')
                  .after_error_response(/.*/) do |code, body, _header, message|
                    puts "Warning: Could not fetch project-resource from link for service #{service_id}: #{code} - #{message}"
                    nil
                  end
                
                if pr_response && pr_response['data']
                  project_resource_id = pr_response['data']['id']
                end
              rescue => e
                puts "Warning: Could not fetch project-resource from link for service #{service_id}: #{e.message}"
              end
            end
          end
          
          # Store the mapping for this service
          if project_resource_id.present?
            service_to_project_resource_map[service_id] = project_resource_id
            project_resource_ids << project_resource_id unless project_resource_ids.include?(project_resource_id)
          end
        end

        # Fetch project-resource details for each unique ID
        standard_resource_ids = []
        project_resource_ids.each do |resource_id|
          begin
            resource_response = get("/#{account_slug}/v1/project-resources/#{resource_id}")
              .after_error_response(/.*/) do |code, body, _header, message|
                puts "Warning: Could not fetch project-resource #{resource_id}: #{code} - #{message}"
                nil
              end
            
            if resource_response && resource_response['data']
              resource_data = resource_response['data']
              # Store the resource name and other details from attributes.resource
              resource_info = resource_data.dig('attributes', 'resource')
              standard_resource_id = resource_info&.dig('resource_id')
              
              # Collect standard resource IDs
              if standard_resource_id.present?
                standard_resource_id_int = standard_resource_id.to_i
                standard_resource_ids << standard_resource_id_int unless standard_resource_ids.include?(standard_resource_id_int)
              end
              
              project_resources_map[resource_id] = {
                name: resource_info&.dig('name'),
                hourly_rate: resource_info&.dig('hourly_rate'),
                hourly_cost: resource_info&.dig('hourly_cost'),
                resource_id: standard_resource_id,
                project_resource_name: resource_data.dig('attributes', 'name'),
                project_resource_extended_name: resource_data.dig('attributes', 'extended-name'),
                project_resource_description: resource_data.dig('attributes', 'description'),
                project_resource_hourly_rate: resource_data.dig('attributes', 'hourly-rate'),
                project_resource_hourly_cost: resource_data.dig('attributes', 'hourly-cost'),
                project_resource_code: resource_data.dig('attributes', 'code'),
                project_resource_active: resource_data.dig('attributes', 'active')
              }
            end
          rescue => e
            puts "Warning: Could not fetch project-resource #{resource_id}: #{e.message}"
          end
        end
        
        # Fetch standard resource information for all unique standard resource IDs
        standard_resources_map = {}
        standard_resource_ids.each do |standard_resource_id|
          begin
            standard_resource_response = get("/#{account_slug}/v1/resources/#{standard_resource_id}")
              .params(include: 'account,governances')
              .headers('Accept': 'application/vnd.api+json')
              .after_error_response(/.*/) do |code, body, _header, message|
                puts "Warning: Could not fetch standard resource #{standard_resource_id}: #{code} - #{message}"
                nil
              end
            
            if standard_resource_response && standard_resource_response['data']
              standard_resource_data = standard_resource_response['data']
              standard_resources_map[standard_resource_id] = {
                resource_id: standard_resource_id,
                resource_type: standard_resource_data['type'],
                resource_active: standard_resource_data.dig('attributes', 'active'),
                resource_name: standard_resource_data.dig('attributes', 'name'),
                resource_external_name: standard_resource_data.dig('attributes', 'external-name'),
                resource_description: standard_resource_data.dig('attributes', 'description'),
                resource_hourly_rate: standard_resource_data.dig('attributes', 'hourly-rate'),
                resource_hourly_cost: standard_resource_data.dig('attributes', 'hourly-cost')
              }
            end
          rescue => e
            puts "Warning: Could not fetch standard resource #{standard_resource_id}: #{e.message}"
          end
        end
        
        # Update project_resources_map with standard resource info
        project_resources_map.each do |project_resource_id, info|
          standard_resource_id = info[:resource_id]&.to_i
          if standard_resource_id.present? && standard_resource_id > 0 && standard_resources_map[standard_resource_id]
            project_resources_map[project_resource_id].merge!(standard_resources_map[standard_resource_id])
          end
        end

        # Process and sort the data
        processed_services = all_data.map do |service|
          # Get phase information
          phase_data = service.dig('relationships', 'project-phase', 'data')
          phase_id = phase_data&.dig('id')
          
          if phase_id && phases_map[phase_id]
            phase_name = phases_map[phase_id][:name]
            phase_sequence = phases_map[phase_id][:position]
          elsif phase_id
            # Phase exists but not in our map (from included data)
            included_phase = response['included']&.find { |inc| inc['id'] == phase_id && inc['type'] == 'project-phases' }
            if included_phase
              phase_name = included_phase['attributes']['name']
              phase_sequence = included_phase['attributes']['position']
            else
              phase_name = "Unknown Phase"
              phase_sequence = 999
            end
          else
            phase_name = "No Phase"
            phase_sequence = nil
          end

          # Calculate overall sequence
          service_position = service['attributes']['position'] || 0
          overall_sequence = if phase_sequence
            (phase_sequence * 1000) + service_position
          else
            (999 * 1000) + service_position
          end

          # Check for subservices
          has_subservices = nil
          subservices = []
          
          begin
            subservices_response = get("/#{account_slug}/v1/project-services/#{service['id']}/project-subservices")
              .params({ 'filter[active]' => 'true' })
              .after_error_response(/.*/) do |code, body, _header, message|
                puts "Warning: Could not fetch subservices for service #{service['id']}: #{code} - #{message}"
                # Don't error here, just continue with has_subservices = nil
              end
            
            if subservices_response && subservices_response['data']
              has_subservices = subservices_response['data'].length > 0
              if input['include_subservices']
                subservices = subservices_response['data']
              end
            else
              has_subservices = false
            end
          rescue => e
            puts "Warning: Could not fetch subservices for service #{service['id']}: #{e.message}"
            has_subservices = nil
          end

          # Always get project-resource and standard resource information
          project_resource_info = nil
          # Look up the project-resource ID from our mapping (already collected in first phase)
          project_resource_id = service_to_project_resource_map[service['id']]
          
          # If we have a project-resource ID, get the info from our map
          if project_resource_id && project_resources_map[project_resource_id]
            project_resource_info = project_resources_map[project_resource_id]
          end

          # Add phase information and subservices to the service
          service_data = {
            'phase_name' => phase_name,
            'phase_sequence' => phase_sequence,
            'phase_id' => phase_id,
            'overall_sequence' => overall_sequence,
            'has_subservices' => has_subservices
          }
          
          # Add project-resource and standard resource information if available
          if project_resource_info
            # Standard resource fields (from attributes.resource in project-resource)
            service_data['resource_name'] = project_resource_info[:name]
            service_data['resource_hourly_rate'] = project_resource_info[:hourly_rate]
            service_data['resource_hourly_cost'] = project_resource_info[:hourly_cost]
            service_data['resource_id'] = project_resource_info[:resource_id]&.to_i
            # Convert rates to cents
            if project_resource_info[:hourly_rate].present?
              service_data['resource_hourly_rate_in_cents'] = (project_resource_info[:hourly_rate].to_f * 100).to_i
            end
            if project_resource_info[:hourly_cost].present?
              service_data['resource_hourly_cost_in_cents'] = (project_resource_info[:hourly_cost].to_f * 100).to_i
            end
            
            # Project resource fields
            service_data['project_resource_name'] = project_resource_info[:project_resource_name]
            service_data['project_resource_extended_name'] = project_resource_info[:project_resource_extended_name]
            service_data['project_resource_description'] = project_resource_info[:project_resource_description]
            service_data['project_resource_hourly_rate'] = project_resource_info[:project_resource_hourly_rate]
            service_data['project_resource_hourly_cost'] = project_resource_info[:project_resource_hourly_cost]
            service_data['project_resource_code'] = project_resource_info[:project_resource_code]
            service_data['project_resource_active'] = project_resource_info[:project_resource_active]
            # Convert rates to cents
            if project_resource_info[:project_resource_hourly_rate].present?
              service_data['project_resource_hourly_rate_in_cents'] = (project_resource_info[:project_resource_hourly_rate].to_f * 100).to_i
            end
            if project_resource_info[:project_resource_hourly_cost].present?
              service_data['project_resource_hourly_cost_in_cents'] = (project_resource_info[:project_resource_hourly_cost].to_f * 100).to_i
            end
            
            # Standard resource fields (from full standard resource API call)
            service_data['standard_resource_id'] = project_resource_info[:resource_id]&.to_i
            service_data['standard_resource_type'] = project_resource_info[:resource_type]
            service_data['standard_resource_active'] = project_resource_info[:resource_active]
            service_data['standard_resource_name'] = project_resource_info[:resource_name]
            service_data['standard_resource_external_name'] = project_resource_info[:resource_external_name]
            service_data['standard_resource_description'] = project_resource_info[:resource_description]
            service_data['standard_resource_hourly_rate'] = project_resource_info[:resource_hourly_rate]
            service_data['standard_resource_hourly_cost'] = project_resource_info[:resource_hourly_cost]
            # Convert rates to cents
            if project_resource_info[:resource_hourly_rate].present?
              service_data['standard_resource_hourly_rate_in_cents'] = (project_resource_info[:resource_hourly_rate].to_f * 100).to_i
            end
            if project_resource_info[:resource_hourly_cost].present?
              service_data['standard_resource_hourly_cost_in_cents'] = (project_resource_info[:resource_hourly_cost].to_f * 100).to_i
            end
          end
          
          # Only include subservices array if requested
          if input['include_subservices']
            service_data['subservices'] = subservices
          end
          
          # Add integer conversions for hours and costs in the service attributes
          service_attrs = service['attributes'] || {}
          if service_attrs['override-hours'].present?
            service_attrs['override_hours_in_minutes'] = (service_attrs['override-hours'].to_f * 60).to_i
          end
          if service_attrs['actual-hours'].present?
            service_attrs['actual_hours_in_minutes'] = (service_attrs['actual-hours'].to_f * 60).to_i
          end
          if service_attrs['extended-hours'].present?
            service_attrs['extended_hours_in_minutes'] = (service_attrs['extended-hours'].to_f * 60).to_i
          end
          if service_attrs['total-hours'].present?
            service_attrs['total_hours_in_minutes'] = (service_attrs['total-hours'].to_f * 60).to_i
          end
          
          # Add integer conversions for calculated-pricing
          if service_attrs['calculated-pricing'].present?
            calc_pricing = service_attrs['calculated-pricing']
            if calc_pricing['service_cost'].present?
              calc_pricing['service_cost_in_cents'] = (calc_pricing['service_cost'].to_f * 100).to_i
            end
            if calc_pricing['extended_hours'].present?
              calc_pricing['extended_hours_in_minutes'] = (calc_pricing['extended_hours'].to_f * 60).to_i
            end
            if calc_pricing['service_revenue'].present?
              calc_pricing['service_revenue_in_cents'] = (calc_pricing['service_revenue'].to_f * 100).to_i
            end
          end
          
          service.merge(service_data)
        end

        # Sort by position attribute
        processed_services.sort_by! { |service| service.dig('attributes', 'position') || 0 }
        
        # Reverse if last_to_first is selected
        processed_services.reverse! if input['sort_order'] == 'last_to_first'

        # Format output based on user preference
        if input['output_format'] == 'grouped'
          # Group by phase
          grouped_services = {}
          processed_services.each do |service|
            phase_key = service['phase_name']
            grouped_services[phase_key] ||= {
              phase_name: service['phase_name'],
              phase_sequence: service['phase_sequence'],
              phase_id: service['phase_id'],
              services: []
            }
            grouped_services[phase_key][:services] << service
          end

          # Sort services within each phase by position (already sorted above, but ensure consistency)
          grouped_services.each do |_phase_key, phase_group|
            phase_group[:services].sort_by! { |service| service.dig('attributes', 'position') || 0 }
            phase_group[:services].reverse! if input['sort_order'] == 'last_to_first'
          end

          # Sort phases and convert to array
          sorted_phases = grouped_services.values.sort_by { |phase| phase[:phase_sequence] || 999 }
          
          {
            data: sorted_phases,
            meta: {
              total_count: processed_services.size,
              format: 'grouped'
            }
          }
        else
          # Flat array format
          {
            data: processed_services,
            meta: {
              total_count: processed_services.size,
              format: 'flat'
            }
          }
        end
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: "data",
            type: "array",
            of: "object",
            properties: object_definitions['project_service'].concat([
              { name: "phase_name", type: "string", label: "Phase Name" },
              { name: "phase_sequence", type: "integer", label: "Phase Sequence" },
              { name: "phase_id", type: "integer", label: "Phase ID" },
              { name: "overall_sequence", type: "integer", label: "Overall Sequence" },
              { name: "has_subservices", type: "boolean", label: "Has Subservices", optional: true },
              { 
                name: "subservices", 
                type: "array", 
                of: "object", 
                label: "Subservices",
                optional: true,
                properties: object_definitions['project_subservice']
              },
              { name: "resource_name", type: "string", label: "Resource Name", optional: true },
              { name: "resource_hourly_rate", type: "string", label: "Resource Hourly Rate", optional: true },
              { name: "resource_hourly_cost", type: "string", label: "Resource Hourly Cost", optional: true },
              { name: "resource_hourly_rate_in_cents", type: "integer", label: "Resource Hourly Rate (in cents)", optional: true },
              { name: "resource_hourly_cost_in_cents", type: "integer", label: "Resource Hourly Cost (in cents)", optional: true },
              { name: "resource_id", type: "integer", label: "Resource ID", optional: true },
              { name: "project_resource_name", type: "string", label: "Project Resource Name", optional: true },
              { name: "project_resource_extended_name", type: "string", label: "Project Resource Extended Name", optional: true },
              { name: "project_resource_description", type: "string", label: "Project Resource Description", optional: true },
              { name: "project_resource_hourly_rate", type: "string", label: "Project Resource Hourly Rate", optional: true },
              { name: "project_resource_hourly_cost", type: "string", label: "Project Resource Hourly Cost", optional: true },
              { name: "project_resource_hourly_rate_in_cents", type: "integer", label: "Project Resource Hourly Rate (in cents)", optional: true },
              { name: "project_resource_hourly_cost_in_cents", type: "integer", label: "Project Resource Hourly Cost (in cents)", optional: true },
              { name: "project_resource_code", type: "string", label: "Project Resource Code", optional: true },
              { name: "project_resource_active", type: "boolean", label: "Project Resource Active", optional: true },
              { name: "standard_resource_id", type: "integer", label: "Standard Resource ID", optional: true },
              { name: "standard_resource_type", type: "string", label: "Standard Resource Type", optional: true },
              { name: "standard_resource_active", type: "boolean", label: "Standard Resource Active", optional: true },
              { name: "standard_resource_name", type: "string", label: "Standard Resource Name", optional: true },
              { name: "standard_resource_external_name", type: "string", label: "Standard Resource External Name", optional: true },
              { name: "standard_resource_description", type: "string", label: "Standard Resource Description", optional: true },
              { name: "standard_resource_hourly_rate", type: "string", label: "Standard Resource Hourly Rate", optional: true },
              { name: "standard_resource_hourly_cost", type: "string", label: "Standard Resource Hourly Cost", optional: true },
              { name: "standard_resource_hourly_rate_in_cents", type: "integer", label: "Standard Resource Hourly Rate (in cents)", optional: true },
              { name: "standard_resource_hourly_cost_in_cents", type: "integer", label: "Standard Resource Hourly Cost (in cents)", optional: true }
            ])
          },
          {
            name: "meta",
            type: "object",
            properties: [
              { name: "total_count", type: "integer", label: "Total Count" },
              { name: "format", type: "string", label: "Output Format" }
            ]
          }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        {
          "data" => [
            {
              "id" => "503267",
              "type" => "project-services",
              "links" => {
                "synchronize-standard" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/503267/synchronize-standard",
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/503267"
              },
              "attributes" => {
                "active" => true,
                "name" => "Cisco Business Edition 6000",
                "quantity" => 1,
                "override-hours" => "0.0",
                "actual-hours" => nil,
                "position" => 1,
                "service-type" => "professional_services",
                "lob-id" => 34847,
                "payment-frequency" => "one_time",
                "task-source" => "standard",
                "languages" => {
                  "out" => "Network Remediation\r\nTroubleshooting of any kind prior to the cut over to the new call manager system",
                  "customer" => "Access to all appropriate resources if questions may arise",
                  "assumptions" => "Clients network can support VOIP",
                  "deliverables" => "Cisco Business Edition As-built Documenation",
                  "sow_language" => "",
                  "design_language" => "",
                  "planning_language" => "",
                  "implementation_language" => "Install and configure a Cisco Business Edition 6000 per the previous conversations with our team, specifically by implementing the following:"
                },
                "variable-rates" => {},
                "calculated-pricing" => {
                  "service_cost" => "0.0",
                  "material_cost" => 0,
                  "extended_hours" => "0.0",
                  "service_revenue" => "0.0",
                  "material_revenue" => 0
                },
                "extended-hours" => "0.0",
                "total-hours" => "12.5",
                "external-resource-name" => nil,
                "sku" => nil,
                "service-description" => "Install and configure a Cisco Business Edition 6000 per the previous conversations with our team, specifically by implementing the following:",
                "target-margin" => nil,
                "payment-method" => "payment_term_schedule",
                "resource-rate-id" => nil,
                "custom-hours?" => nil
              },
              "relationships" => {
                "project" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/503267/relationships/project",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/503267/project"
                  }
                },
                "project-phase" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/503267/relationships/project-phase",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/503267/project-phase"
                  },
                  "data" => {
                    "type" => "project-phases",
                    "id" => "602419"
                  }
                }
              },
              "phase_name" => "Implement",
              "phase_sequence" => 3,
              "phase_id" => "602419",
              "overall_sequence" => 3001,
              "has_subservices" => true,
              "resource_name" => "Engineer",
              "resource_hourly_rate" => "150.0",
              "resource_hourly_cost" => "100.0",
              "resource_id" => 15866,
              "project_resource_name" => "Engineer",
              "project_resource_extended_name" => "Engineer",
              "project_resource_description" => nil,
              "project_resource_hourly_rate" => "150.0",
              "project_resource_hourly_cost" => "100.0",
              "project_resource_code" => nil,
              "project_resource_active" => true,
              "standard_resource_id" => "15866",
              "standard_resource_type" => "resources",
              "standard_resource_active" => true,
              "standard_resource_name" => "Engineer",
              "standard_resource_external_name" => nil,
              "standard_resource_description" => nil,
              "standard_resource_hourly_rate" => "150.0",
              "standard_resource_hourly_cost" => "100.0"
            },
            {
              "id" => "526936",
              "type" => "project-services",
              "links" => {
                "synchronize-standard" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/526936/synchronize-standard",
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/526936"
              },
              "attributes" => {
                "active" => true,
                "name" => "Switch",
                "quantity" => 1,
                "override-hours" => "2.0",
                "actual-hours" => nil,
                "position" => 7,
                "service-type" => "professional_services",
                "lob-id" => 34837,
                "payment-frequency" => "one_time",
                "task-source" => "standard",
                "languages" => {
                  "out" => "",
                  "customer" => "",
                  "assumptions" => "",
                  "deliverables" => "Switch as-built documentation",
                  "sow_language" => "",
                  "design_language" => "",
                  "planning_language" => "",
                  "implementation_language" => "Configure and implement a global system configuration per device best practices by disabling unneeded services and/or by following the specified customer provided standards."
                },
                "variable-rates" => {
                  "hours" => [
                    {
                      "base_amount" => "0.0",
                      "unit_amount" => "2.0",
                      "minimum_quantity" => "1.0"
                    }
                  ]
                },
                "calculated-pricing" => {
                  "service_cost" => "200.0",
                  "material_cost" => 0,
                  "extended_hours" => "2.0",
                  "service_revenue" => "300.0",
                  "material_revenue" => 0
                },
                "extended-hours" => "2.0",
                "total-hours" => "5.0",
                "external-resource-name" => nil,
                "sku" => nil,
                "service-description" => "Configure and implement a global system configuration per device best practices by disabling unneeded services and/or by following the specified customer provided standards.",
                "target-margin" => nil,
                "payment-method" => "payment_term_schedule",
                "resource-rate-id" => nil,
                "custom-hours?" => nil
              },
              "relationships" => {
                "project" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/526936/relationships/project",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/526936/project"
                  }
                },
                "project-phase" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/526936/relationships/project-phase",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/526936/project-phase"
                  },
                  "data" => {
                    "type" => "project-phases",
                    "id" => "602419"
                  }
                }
              },
              "phase_name" => "Implement",
              "phase_sequence" => 3,
              "phase_id" => "602419",
              "overall_sequence" => 3007,
              "has_subservices" => true,
              "resource_name" => "Engineer",
              "resource_hourly_rate" => "150.0",
              "resource_hourly_cost" => "100.0",
              "resource_id" => 15866,
              "project_resource_name" => "Engineer",
              "project_resource_extended_name" => "Engineer",
              "project_resource_description" => nil,
              "project_resource_hourly_rate" => "150.0",
              "project_resource_hourly_cost" => "100.0",
              "project_resource_code" => nil,
              "project_resource_active" => true,
              "standard_resource_id" => "15866",
              "standard_resource_type" => "resources",
              "standard_resource_active" => true,
              "standard_resource_name" => "Engineer",
              "standard_resource_external_name" => nil,
              "standard_resource_description" => nil,
              "standard_resource_hourly_rate" => "150.0",
              "standard_resource_hourly_cost" => "100.0",
              "subservices" => [
                {
                  "id" => "1462926",
                  "type" => "project-subservices",
                  "links" => {
                    "synchronize-standard" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926/synchronize-standard",
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926"
                  },
                  "attributes" => {
                    "active" => true,
                    "name" => "L3 Services - BGP",
                    "quantity" => 4,
                    "extended-hours" => "2.0",
                    "override-hours" => "0.5",
                    "actual-hours" => nil,
                    "position" => 1,
                    "service-type" => "professional_services",
                    "payment-frequency" => "one_time",
                    "task-source" => "standard",
                    "languages" => {
                      "out" => "",
                      "customer" => "",
                      "assumptions" => "BGP Peering requirements can be provided",
                      "deliverables" => "BGP configurations",
                      "sow_language" => "",
                      "design_language" => "",
                      "planning_language" => "",
                      "implementation_language" => "Configure L3 protocols to support BGP peering and clients requirements"
                    },
                    "variable-rates" => {
                      "hours" => []
                    },
                    "calculated-pricing" => {
                      "service_cost" => "200.0",
                      "material_cost" => 0,
                      "extended_hours" => "2.0",
                      "service_revenue" => "300.0",
                      "material_revenue" => 0
                    },
                    "external-resource-name" => nil,
                    "sku" => nil,
                    "service-description" => "Configure L3 protocols to support BGP peering and clients requirements",
                    "payment-method" => "payment_term_schedule",
                    "resource-rate-id" => nil,
                    "custom-hours?" => nil
                  },
                  "relationships" => {
                    "account" => {
                      "links" => {
                        "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926/relationships/account",
                        "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926/account"
                      }
                    },
                    "project" => {
                      "links" => {
                        "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926/relationships/project",
                        "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926/project"
                      }
                    },
                    "project-service" => {
                      "links" => {
                        "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926/relationships/project-service",
                        "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926/project-service"
                      }
                    }
                  }
                }
              ]
            }
          ],
          "meta" => {
            "total_count" => 2,
            "format" => "flat"
          }
        }
      end
    },

    list_project_subservices: {
      title: "List Project Subservices",
      subtitle: "Get project subservices for a specific project service",
      description: "Get all <span class='provider'>project subservices</span> associated with a specific <span class='provider'>project service</span> in <span class='provider'>ScopeStack</span>",
      help: "Retrieves all project subservices that are associated with a specific project service. This is more useful than getting all project subservices as it provides context-specific results.",

      input_fields: lambda do |_object_definitions|
        [
          {
            name: "project_service_id",
            label: "Project Service ID",
            type: "integer",
            control_type: "number",
            optional: false,
            hint: "The ID of the project service to get subservices for"
          },
          {
            name: "sort_order",
            label: "Sort Order",
            type: "string",
            control_type: "select",
            pick_list: [
              ["First to Last (1, 2, 3...)", "first_to_last"],
              ["Last to First (...3, 2, 1)", "last_to_first"]
            ],
            default: "first_to_last",
            optional: false,
            hint: "Choose the order to sort results by position. 'First to Last' shows position 1 first, 'Last to First' shows the highest position first."
          },
        ]
      end,

      execute: lambda do |connection, input|
        # Get account information using the reusable method
        account_info = call('get_account_info', connection)
        account_slug = account_info[:account_slug]

        # Build parameters - hardcode active filter to true
        params = { 'filter[active]' => 'true' }

        # Make the API call
        response = get("/#{account_slug}/v1/project-services/#{input['project_service_id']}/project-subservices")
                  .headers('Accept': 'application/vnd.api+json')
                  .params(params)
                  .after_error_response(/.*/) do |code, body, _header, message|
                    case code
                    when 404
                      error("Project service not found with ID: #{input['project_service_id']}")
                    when 401, 403
                      error("Authentication failed or insufficient permissions. Please check your credentials: #{message}")
                    when 500..599
                      error("ScopeStack server error occurred. Please try again later: #{message}")
                    else
                      error("Failed to fetch project subservices (#{code}): #{message}: #{body}")
                    end
                  end

        # Sort by position attribute if data exists
        sorted_data = response['data']
        if sorted_data && sorted_data.is_a?(Array)
          sorted_data = sorted_data.sort_by do |subservice|
            subservice.dig('attributes', 'position') || 0
          end
          
          # Reverse if last_to_first is selected
          sorted_data = sorted_data.reverse if input['sort_order'] == 'last_to_first'
        end

        # Always fetch project-resource and standard resource information
        if sorted_data && sorted_data.is_a?(Array)
          # First, fetch the parent service's project-resource as a fallback
          parent_service_resource_id = nil
          parent_service_resource_info = nil
          begin
            parent_service_response = get("/#{account_slug}/v1/project-services/#{input['project_service_id']}")
              .headers('Accept': 'application/vnd.api+json')
              .after_error_response(/.*/) do |code, body, _header, message|
                puts "Warning: Could not fetch parent service #{input['project_service_id']}: #{code} - #{message}"
                nil
              end
            
            if parent_service_response && parent_service_response['data']
              parent_service = parent_service_response['data']
              # Try to get project-resource ID from parent service relationships
              parent_project_resource_data = parent_service.dig('relationships', 'project-resource', 'data')
              if parent_project_resource_data && parent_project_resource_data['id']
                parent_service_resource_id = parent_project_resource_data['id']
              else
                # If not in data, try to fetch from the related link
                parent_project_resource_link = parent_service.dig('relationships', 'project-resource', 'links', 'related') || 
                                             parent_service.dig('relationships', 'project-resource', 'links', 'self')
                if parent_project_resource_link
                  begin
                    uri = URI.parse(parent_project_resource_link)
                    path = uri.path
                    pr_response = get(path)
                      .headers('Accept': 'application/vnd.api+json')
                      .after_error_response(/.*/) do |code, body, _header, message|
                        puts "Warning: Could not fetch parent service project-resource from link: #{code} - #{message}"
                        nil
                      end
                    
                    if pr_response && pr_response['data']
                      parent_service_resource_id = pr_response['data']['id']
                    end
                  rescue => e
                    puts "Warning: Could not fetch parent service project-resource from link: #{e.message}"
                  end
                end
              end
            end
          rescue => e
            puts "Warning: Could not fetch parent service for fallback resource: #{e.message}"
          end
          
          # Collect all unique project-resource IDs from subservices and create a mapping
          subservice_to_project_resource_map = {} # Map subservice_id -> project_resource_id
          project_resource_ids = sorted_data.map do |subservice|
            subservice_id = subservice['id']
            project_resource_id = nil
            
            # Try to get project-resource ID from relationships data first
            project_resource_data = subservice.dig('relationships', 'project-resource', 'data')
            if project_resource_data && project_resource_data['id']
              project_resource_id = project_resource_data['id']
            else
              # If not in data, try to extract from links or fetch from the link
              project_resource_link = subservice.dig('relationships', 'project-resource', 'links', 'related') || 
                                     subservice.dig('relationships', 'project-resource', 'links', 'self')
              if project_resource_link
                # First try regex extraction
                match = project_resource_link.match(%r{/project-resources/(\d+)})
                if match
                  project_resource_id = match[1]
                else
                  # If regex doesn't match, try fetching from the link
                  begin
                    uri = URI.parse(project_resource_link)
                    path = uri.path
                    pr_response = get(path)
                      .headers('Accept': 'application/vnd.api+json')
                      .after_error_response(/.*/) do |code, body, _header, message|
                        puts "Warning: Could not fetch subservice project-resource from link for subservice #{subservice_id}: #{code} - #{message}"
                        nil
                      end
                    
                    if pr_response && pr_response['data']
                      project_resource_id = pr_response['data']['id']
                    end
                  rescue => e
                    puts "Warning: Could not fetch subservice project-resource from link for subservice #{subservice_id}: #{e.message}"
                  end
                end
              end
            end
            
            # Store the mapping for this subservice
            if project_resource_id.present?
              subservice_to_project_resource_map[subservice_id] = project_resource_id
              project_resource_id
            else
              nil
            end
          end.compact.uniq
          
          # Add parent service resource ID if it exists and isn't already in the list
          if parent_service_resource_id.present?
            project_resource_ids << parent_service_resource_id unless project_resource_ids.include?(parent_service_resource_id)
          end

          # Fetch project-resource details for each unique ID
          standard_resource_ids = []
          project_resources_map = {}
          project_resource_ids.each do |resource_id|
            begin
              resource_response = get("/#{account_slug}/v1/project-resources/#{resource_id}")
                .after_error_response(/.*/) do |code, body, _header, message|
                  puts "Warning: Could not fetch project-resource #{resource_id}: #{code} - #{message}"
                  nil
                end
              
              if resource_response && resource_response['data']
                resource_data = resource_response['data']
                # Store the resource name and other details from attributes.resource
                resource_info = resource_data.dig('attributes', 'resource')
                standard_resource_id = resource_info&.dig('resource_id')
                
                # Collect standard resource IDs
                if standard_resource_id.present?
                  standard_resource_id_int = standard_resource_id.to_i
                  standard_resource_ids << standard_resource_id_int unless standard_resource_ids.include?(standard_resource_id_int)
                end
                
                project_resources_map[resource_id] = {
                  name: resource_info&.dig('name'),
                  hourly_rate: resource_info&.dig('hourly_rate'),
                  hourly_cost: resource_info&.dig('hourly_cost'),
                  resource_id: standard_resource_id,
                  project_resource_name: resource_data.dig('attributes', 'name'),
                  project_resource_extended_name: resource_data.dig('attributes', 'extended-name'),
                  project_resource_description: resource_data.dig('attributes', 'description'),
                  project_resource_hourly_rate: resource_data.dig('attributes', 'hourly-rate'),
                  project_resource_hourly_cost: resource_data.dig('attributes', 'hourly-cost'),
                  project_resource_code: resource_data.dig('attributes', 'code'),
                  project_resource_active: resource_data.dig('attributes', 'active')
                }
              end
            rescue => e
              puts "Warning: Could not fetch project-resource #{resource_id}: #{e.message}"
            end
          end
          
          # Fetch standard resource information for all unique standard resource IDs
          standard_resources_map = {}
          standard_resource_ids.each do |standard_resource_id|
            begin
              standard_resource_response = get("/#{account_slug}/v1/resources/#{standard_resource_id}")
                .params(include: 'account,governances')
                .headers('Accept': 'application/vnd.api+json')
                .after_error_response(/.*/) do |code, body, _header, message|
                  puts "Warning: Could not fetch standard resource #{standard_resource_id}: #{code} - #{message}"
                  nil
                end
              
              if standard_resource_response && standard_resource_response['data']
                standard_resource_data = standard_resource_response['data']
                standard_resources_map[standard_resource_id] = {
                  resource_id: standard_resource_id,
                  resource_type: standard_resource_data['type'],
                  resource_active: standard_resource_data.dig('attributes', 'active'),
                  resource_name: standard_resource_data.dig('attributes', 'name'),
                  resource_external_name: standard_resource_data.dig('attributes', 'external-name'),
                  resource_description: standard_resource_data.dig('attributes', 'description'),
                  resource_hourly_rate: standard_resource_data.dig('attributes', 'hourly-rate'),
                  resource_hourly_cost: standard_resource_data.dig('attributes', 'hourly-cost')
                }
              end
            rescue => e
              puts "Warning: Could not fetch standard resource #{standard_resource_id}: #{e.message}"
            end
          end
          
          # Update project_resources_map with standard resource info
          project_resources_map.each do |project_resource_id, info|
            standard_resource_id = info[:resource_id]&.to_i
            if standard_resource_id.present? && standard_resource_id > 0 && standard_resources_map[standard_resource_id]
              project_resources_map[project_resource_id].merge!(standard_resources_map[standard_resource_id])
            end
          end

          # Add project-resource and standard resource information to each subservice
          sorted_data = sorted_data.map do |subservice|
            # Look up the project-resource ID from our mapping (already collected in first phase)
            subservice_id = subservice['id']
            project_resource_id = subservice_to_project_resource_map[subservice_id]
            
            # Fallback: Only use parent service's resource if subservice truly has no resource
            if !project_resource_id || project_resource_id.to_s.strip.empty?
              if parent_service_resource_id.present?
                project_resource_id = parent_service_resource_id
              end
            end
            
            # If we have a project-resource ID, get the info from our map
            if project_resource_id && project_resources_map[project_resource_id]
              resource_info = project_resources_map[project_resource_id]
              merged_data = {
                # Standard resource fields (from attributes.resource in project-resource)
                'resource_name' => resource_info[:name],
                'resource_hourly_rate' => resource_info[:hourly_rate],
                'resource_hourly_cost' => resource_info[:hourly_cost],
                'resource_id' => resource_info[:resource_id],
                # Project resource fields
                'project_resource_name' => resource_info[:project_resource_name],
                'project_resource_extended_name' => resource_info[:project_resource_extended_name],
                'project_resource_description' => resource_info[:project_resource_description],
                'project_resource_hourly_rate' => resource_info[:project_resource_hourly_rate],
                'project_resource_hourly_cost' => resource_info[:project_resource_hourly_cost],
                'project_resource_code' => resource_info[:project_resource_code],
                'project_resource_active' => resource_info[:project_resource_active],
                # Standard resource fields (from full standard resource API call)
                'standard_resource_id' => resource_info[:resource_id]&.to_i,
                'standard_resource_type' => resource_info[:resource_type],
                'standard_resource_active' => resource_info[:resource_active],
                'standard_resource_name' => resource_info[:resource_name],
                'standard_resource_external_name' => resource_info[:resource_external_name],
                'standard_resource_description' => resource_info[:resource_description],
                'standard_resource_hourly_rate' => resource_info[:resource_hourly_rate],
                'standard_resource_hourly_cost' => resource_info[:resource_hourly_cost]
              }
              
              # Add integer conversions for rates (cents)
              if resource_info[:hourly_rate].present?
                merged_data['resource_hourly_rate_in_cents'] = (resource_info[:hourly_rate].to_f * 100).to_i
              end
              if resource_info[:hourly_cost].present?
                merged_data['resource_hourly_cost_in_cents'] = (resource_info[:hourly_cost].to_f * 100).to_i
              end
              if resource_info[:project_resource_hourly_rate].present?
                merged_data['project_resource_hourly_rate_in_cents'] = (resource_info[:project_resource_hourly_rate].to_f * 100).to_i
              end
              if resource_info[:project_resource_hourly_cost].present?
                merged_data['project_resource_hourly_cost_in_cents'] = (resource_info[:project_resource_hourly_cost].to_f * 100).to_i
              end
              if resource_info[:resource_hourly_rate].present?
                merged_data['standard_resource_hourly_rate_in_cents'] = (resource_info[:resource_hourly_rate].to_f * 100).to_i
              end
              if resource_info[:resource_hourly_cost].present?
                merged_data['standard_resource_hourly_cost_in_cents'] = (resource_info[:resource_hourly_cost].to_f * 100).to_i
              end
              
              merged_subservice = subservice.merge(merged_data)
              
              # Add integer conversions for hours and costs in the subservice attributes
              subservice_attrs = merged_subservice['attributes'] || {}
              if subservice_attrs['extended-hours'].present?
                subservice_attrs['extended_hours_in_minutes'] = (subservice_attrs['extended-hours'].to_f * 60).to_i
              end
              if subservice_attrs['override-hours'].present?
                subservice_attrs['override_hours_in_minutes'] = (subservice_attrs['override-hours'].to_f * 60).to_i
              end
              if subservice_attrs['actual-hours'].present?
                subservice_attrs['actual_hours_in_minutes'] = (subservice_attrs['actual-hours'].to_f * 60).to_i
              end
              
              # Add integer conversions for calculated-pricing
              if subservice_attrs['calculated-pricing'].present?
                calc_pricing = subservice_attrs['calculated-pricing']
                if calc_pricing['service_cost'].present?
                  calc_pricing['service_cost_in_cents'] = (calc_pricing['service_cost'].to_f * 100).to_i
                end
                if calc_pricing['extended_hours'].present?
                  calc_pricing['extended_hours_in_minutes'] = (calc_pricing['extended_hours'].to_f * 60).to_i
                end
                if calc_pricing['service_revenue'].present?
                  calc_pricing['service_revenue_in_cents'] = (calc_pricing['service_revenue'].to_f * 100).to_i
                end
              end
              
              merged_subservice
            else
              # Even if no resource info, still add conversions for subservice attributes
              subservice_attrs = subservice['attributes'] || {}
              if subservice_attrs['extended-hours'].present?
                subservice_attrs['extended_hours_in_minutes'] = (subservice_attrs['extended-hours'].to_f * 60).to_i
              end
              if subservice_attrs['override-hours'].present?
                subservice_attrs['override_hours_in_minutes'] = (subservice_attrs['override-hours'].to_f * 60).to_i
              end
              if subservice_attrs['actual-hours'].present?
                subservice_attrs['actual_hours_in_minutes'] = (subservice_attrs['actual-hours'].to_f * 60).to_i
              end
              
              # Add integer conversions for calculated-pricing
              if subservice_attrs['calculated-pricing'].present?
                calc_pricing = subservice_attrs['calculated-pricing']
                if calc_pricing['service_cost'].present?
                  calc_pricing['service_cost_in_cents'] = (calc_pricing['service_cost'].to_f * 100).to_i
                end
                if calc_pricing['extended_hours'].present?
                  calc_pricing['extended_hours_in_minutes'] = (calc_pricing['extended_hours'].to_f * 60).to_i
                end
                if calc_pricing['service_revenue'].present?
                  calc_pricing['service_revenue_in_cents'] = (calc_pricing['service_revenue'].to_f * 100).to_i
                end
              end
              
              subservice
            end
          end
          
          response['data'] = sorted_data
        end

        response
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: "data",
            type: "array",
            of: "object",
            properties: object_definitions['project_subservice'].concat([
              { name: "resource_name", type: "string", label: "Resource Name", optional: true },
              { name: "resource_hourly_rate", type: "string", label: "Resource Hourly Rate", optional: true },
              { name: "resource_hourly_cost", type: "string", label: "Resource Hourly Cost", optional: true },
              { name: "resource_hourly_rate_in_cents", type: "integer", label: "Resource Hourly Rate (in cents)", optional: true },
              { name: "resource_hourly_cost_in_cents", type: "integer", label: "Resource Hourly Cost (in cents)", optional: true },
              { name: "resource_id", type: "integer", label: "Resource ID", optional: true },
              { name: "project_resource_name", type: "string", label: "Project Resource Name", optional: true },
              { name: "project_resource_extended_name", type: "string", label: "Project Resource Extended Name", optional: true },
              { name: "project_resource_description", type: "string", label: "Project Resource Description", optional: true },
              { name: "project_resource_hourly_rate", type: "string", label: "Project Resource Hourly Rate", optional: true },
              { name: "project_resource_hourly_cost", type: "string", label: "Project Resource Hourly Cost", optional: true },
              { name: "project_resource_hourly_rate_in_cents", type: "integer", label: "Project Resource Hourly Rate (in cents)", optional: true },
              { name: "project_resource_hourly_cost_in_cents", type: "integer", label: "Project Resource Hourly Cost (in cents)", optional: true },
              { name: "project_resource_code", type: "string", label: "Project Resource Code", optional: true },
              { name: "project_resource_active", type: "boolean", label: "Project Resource Active", optional: true },
              { name: "standard_resource_id", type: "integer", label: "Standard Resource ID", optional: true },
              { name: "standard_resource_type", type: "string", label: "Standard Resource Type", optional: true },
              { name: "standard_resource_active", type: "boolean", label: "Standard Resource Active", optional: true },
              { name: "standard_resource_name", type: "string", label: "Standard Resource Name", optional: true },
              { name: "standard_resource_external_name", type: "string", label: "Standard Resource External Name", optional: true },
              { name: "standard_resource_description", type: "string", label: "Standard Resource Description", optional: true },
              { name: "standard_resource_hourly_rate", type: "string", label: "Standard Resource Hourly Rate", optional: true },
              { name: "standard_resource_hourly_cost", type: "string", label: "Standard Resource Hourly Cost", optional: true }
            ])
          },
          {
            name: "meta",
            type: "object",
            properties: [
              {
                name: "permissions",
                type: "object",
                properties: [
                  { name: "view", type: "boolean", label: "View Permission" },
                  { name: "create", type: "boolean", label: "Create Permission" },
                  { name: "manage", type: "boolean", label: "Manage Permission" }
                ]
              },
              { name: "record-count", type: "integer", label: "Record Count" },
              { name: "page-count", type: "integer", label: "Page Count" }
            ]
          },
          {
            name: "links",
            type: "object",
            properties: [
              { name: "first", type: "string", label: "First Page Link" },
              { name: "last", type: "string", label: "Last Page Link" }
            ]
          }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        {
          "data" => [
            {
              "id" => "1462926",
              "type" => "project-subservices",
              "links" => {
                "synchronize-standard" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926/synchronize-standard",
                "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926"
              },
              "attributes" => {
                "active" => true,
                "name" => "L3 Services - BGP",
                "quantity" => 4,
                "extended-hours" => "2.0",
                "override-hours" => "0.5",
                "actual-hours" => nil,
                "position" => 1,
                "service-type" => "professional_services",
                "payment-frequency" => "one_time",
                "task-source" => "standard"
              },
              "relationships" => {
                "project-resource" => {
                  "links" => {
                    "self" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926/relationships/project-resource",
                    "related" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-subservices/1462926/project-resource"
                  },
                  "data" => {
                    "type" => "project-resources",
                    "id" => "275828"
                  }
                }
              },
              "resource_name" => "Engineer",
              "resource_hourly_rate" => "150.0",
              "resource_hourly_cost" => "100.0",
              "resource_id" => 15866,
              "project_resource_name" => "Engineer",
              "project_resource_extended_name" => "Engineer",
              "project_resource_description" => nil,
              "project_resource_hourly_rate" => "150.0",
              "project_resource_hourly_cost" => "100.0",
              "project_resource_code" => nil,
              "project_resource_active" => true,
              "standard_resource_id" => "15866",
              "standard_resource_type" => "resources",
              "standard_resource_active" => true,
              "standard_resource_name" => "Engineer",
              "standard_resource_external_name" => nil,
              "standard_resource_description" => nil,
              "standard_resource_hourly_rate" => "150.0",
              "standard_resource_hourly_cost" => "100.0"
            }
          ],
          "meta" => {
            "permissions" => {
              "view" => true,
              "create" => true,
              "manage" => true
            },
            "record-count" => 1,
            "page-count" => 1
          },
          "links" => {
            "first" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/526936/project-subservices?filter%5Bactive%5D=true&page%5Bnumber%5D=1&page%5Bsize%5D=250",
            "last" => "https://api.scopestack.io/zz-workato-testing-account/v1/project-services/526936/project-subservices?filter%5Bactive%5D=true&page%5Bnumber%5D=1&page%5Bsize%5D=250"
          }
        }
      end
    }

  }
}