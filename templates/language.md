
  <div>   <!-- start of {{language_name}} accordion row -->
    <span class="flagspan"><img class="flag" src="flags/svg/{{flag}}.svg" /></span>
    <span class="doublewidespan">{{language_name}}</span>
    <span class="widespan"><span class="hint--top hint--info" data-hint="{{counts.token|tsepk}} tokens {{counts.word|tsepk}} words {{counts.tree|tsepk}} sentences">{{counts.word|tsepk(use_k=true)}}</span></span>

  </div>   <!-- end of {{language_name}} accordion row -->

  <div>   <!-- start of {{language_name}} accordion body -->


    <div class="jquery-ui-subaccordion-closed">     <!-- start of {{language_name}} treebank list -->
       {% for tbank in treebanks %}
     	  <div> <!-- start of {{language_name}} / {{tbank.treebank_code|default("(DEF)",true)}} entry -->
	    <span class="flagspan"></span>
	    <span class="doublewidespan">{{tbank.treebank_code|default("(DEF)",true)}}</span>
	    <span class="doublewidespan">stats-go-here</span>
	  </div>
	  <div>
	  
	    What should go in this space?	     

	    <ul>
              <li>Repository <a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/tree/master">master</a> <a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/tree/dev">dev</a></li>
              <li><a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/blob/master/{{tbank.readme_file}}">README</a></li>
	    </ul>

	    What should go in this space?
	  </div> <!-- end of {{language_name}} / {{tbank.treebank_code|default("(DEF)",true)}} entry -->
       {% endfor %}
    
    </div> <!-- end of {{language_name}} treebank list -->

  Language documentation. What should go in this space?


  </div>   <!-- end of {{language_name}} accordion body -->
