
  <div>   <!-- start of {{language_name}} accordion row -->
    <span class="flagspan"><img class="flag" src="flags/svg/{{flag}}.svg" /></span>
    <span class="doublewidespan">{{language_name}}</span>
    <span class="widespan"><span class="hint--top hint--info" data-hint="{{treebanks|length}} treebank{% if treebanks|length > 1 %}s{% endif %}">{{treebanks|length}}</span></span>
    <span class="widespan"><span class="hint--top hint--info" data-hint="{{counts.token|tsepk}} tokens {{counts.word|tsepk}} words {{counts.tree|tsepk}} sentences">{{counts.word|tsepk(use_k=true)}}</span></span>
    <span class="doublewidespan">{{genres|genre_filter|safe}}</span>
    <span class="triplewidespan">{{language_family}}</span>

  </div>   <!-- end of {{language_name}} accordion row -->

  <div>   <!-- start of {{language_name}} accordion body -->

  <!-- empty space so tooltip fits -->
  <h3> {{language_name}} treebanks</h3>

    <div class="jquery-ui-subaccordion-closed">     <!-- start of {{language_name}} treebank list -->
       {% for tbank in treebanks %}
     	  <div> <!-- start of {{language_name}} / {{tbank.treebank_code|default("Original",true)}} entry -->
	    <span class="flagspan"></span>
	    <span class="doublewidespan">{{tbank.treebank_code|default("Original",true)}}</span>
	    <span class="widespan"><span class="hint--top hint--info" data-hint="{{tbank.counts.token|tsepk}} tokens {{tbank.counts.word|tsepk}} words {{tbank.counts.tree|tsepk}} sentences">{{tbank.counts.word|tsepk(use_k=true)}}</span></span>
	    <span class="widespan">{{tbank.counts|tag_filter|safe}}</span>
	    <!-- <span class="widespan">{{tbank.meta|annotation_filter|safe}}</span> -->
	    <span class="doublewidespan">{{tbank.meta.genre|genre_filter|safe}}</span>
	    <span class="widespan">{{tbank.meta.license|license_filter|safe}}</span>
	  </div>
	  <div>
	  
	    {{tbank.meta.summary|default("Please add a summary section to the treebank readme file",true)}}

	    <ul>
	      <li>Contributors: {{tbank.meta.contributors|contributor_filter}} </li>
              <li>Repository <a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/tree/master">master</a> <a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/tree/dev">dev</a></li>
              <li><a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/blob/dev/{{tbank.readme_file}}">README</a></li>
	    </ul>

	    <p>&nbsp;</p>
	  </div> <!-- end of {{language_name}} / {{tbank.treebank_code|default("Original",true)}} entry -->
       {% endfor %}
    
    </div> <!-- end of {{language_name}} treebank list -->

  <h3> Language documentation </h3>

  Some language documentation.

  </div>   <!-- end of {{language_name}} accordion body -->
